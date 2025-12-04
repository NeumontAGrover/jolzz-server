const std = @import("std");
const net = std.net;
const Server = net.Server;
const Connection = Server.Connection;
const Allocator = std.mem.Allocator;
const Game = @import("game.zig").Game;

const OpcodeValue = enum(u8) {
    Message = 0x1,
    Ping = 0x9,
    Pong = 0xA,
};

pub const JolzzServer = struct {
    ip: []const u8,
    port: u16,
    server: Server,
    allocator: Allocator,
    connections: std.array_list.Aligned(std.Thread, null),
    websocket_instances: std.array_list.Aligned(WebSocketInstance, null),
    shutdown_server: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator, ip: []const u8, port: u16) !Self {
        std.debug.print("Starting server on {s}:{}\n", .{ ip, port });
        const address = try net.Address.resolveIp(ip, port);
        const listener = try address.listen(.{ .reuse_address = true });
        std.debug.print("Listening on {s}:{}\n", .{ ip, port });

        return .{
            .ip = ip,
            .port = port,
            .server = listener,
            .allocator = allocator,
            .connections = try std.ArrayList(std.Thread).initCapacity(allocator, 8),
            .websocket_instances = try std.ArrayList(WebSocketInstance).initCapacity(allocator, 8),
        };
    }

    pub fn deinit(self: *Self) void {
        self.server.deinit();

        self.shutdown_server = true;
        for (self.connections.items) |connection|
            connection.join();

        for (self.websocket_instances.items) |*websocket|
            websocket.deinit();

        self.connections.deinit(self.allocator);
        self.websocket_instances.deinit(self.allocator);
    }

    pub fn connectionListener(self: *Self, games: *std.array_list.Aligned(Game, null)) void {
        while (getConnection(&self.server)) |connection| {
            std.debug.print("Found listener\n", .{});

            var websocket = WebSocketInstance.init(self.allocator, connection) catch
                @panic("Could not create WebSocketInstance");
            errdefer websocket.deinit();

            if (games.items.len == 0)
                games.append(self.allocator, Game.init()) catch @panic("OOM");

            var game = games.getLast();
            if (game.isFull()) {
                game = Game.init();
                games.append(self.allocator, game) catch @panic("OOM");
            }

            const thread = std.Thread.spawn(
                .{ .allocator = self.allocator },
                runSocket,
                .{ &websocket, &self.shutdown_server, &game },
            ) catch |err| {
                std.debug.print("Could not make thread: {any}", .{err});
                return;
            };

            self.connections.append(self.allocator, thread) catch @panic("OOM");
            self.websocket_instances.append(self.allocator, websocket) catch @panic("OOM");
        }
    }

    fn runSocket(websocket: *WebSocketInstance, shutdown_server: *bool, game: *Game) void {
        var receive_buffer: [4096]u8 = undefined;
        var header_offset: usize = 0;

        while (readFromConnection(websocket, receive_buffer[header_offset..])) |receive_length| {
            header_offset += receive_length;
            const header_termination = std.mem.containsAtLeast(
                u8,
                receive_buffer[0..header_offset],
                1,
                "\r\n\r\n",
            );
            if (header_termination) break;
        }

        const header_data = receive_buffer[0..header_offset];
        std.debug.print("{s}\n", .{header_data});
        if (header_data.len == 0) {
            std.debug.print("Connection successful but no data\n", .{});
            return;
        }

        upgradeConnection(websocket, header_data) catch
            @panic("An error occured while upgrading the connection");

        websocket.websocketMessage("hello js from zig!") catch
            std.debug.print("WebSocket write failed\n", .{});

        while (!shutdown_server.*) {
            var buffer: [4096]u8 = undefined;
            const message = websocket.websocketRead(&buffer) catch blk: {
                std.debug.print("WebSocket read failed\n", .{});
                break :blk null;
            };

            if (message) |m| game.getGameMessage(m);

            websocket.heartbeatTimer() catch |err| switch (err) {
                error.HeartbeatFailed => @panic("Heartbeat failed"),
                error.HeartbeatLost => break,
            };
        }
    }

    fn upgradeConnection(websocket: *WebSocketInstance, header_data: []const u8) !void {
        var connection_upgrade = false;
        var websocket_upgrade = false;
        var websocket_version = false;
        var obtained_client_key = false;
        var sec_client_key: [24]u8 = undefined;
        var iterator = std.mem.splitAny(u8, header_data, "\r\n");
        while (iterator.next()) |header| {
            if (!connection_upgrade)
                connection_upgrade = std.mem.containsAtLeast(u8, header, 1, "Connection: Upgrade");

            if (!websocket_upgrade)
                websocket_upgrade = std.mem.containsAtLeast(u8, header, 1, "Upgrade: websocket");

            if (!websocket_version)
                websocket_version = std.mem.containsAtLeast(u8, header, 1, "Sec-WebSocket-Version: 13");

            if (!obtained_client_key and std.mem.containsAtLeast(u8, header, 1, "Sec-WebSocket-Key")) {
                const split_index = std.mem.lastIndexOf(u8, header, ":").? + 2;
                @memcpy(&sec_client_key, header[split_index..]);
                obtained_client_key = true;
            }
        }

        const sec_server_key = try generateServerKey(websocket.allocator, &sec_client_key);
        defer websocket.allocator.free(sec_server_key);
        if (connection_upgrade and websocket_upgrade and websocket_version and obtained_client_key) {
            var writer = websocket.connection.stream.writer(&.{});
            try writer.interface.print(getSwitchingProtocolsResponse(), .{sec_server_key});
            std.debug.print("Connection upgrading\n", .{});
        } else std.debug.print("Not all values supplied for opening the connection\n", .{});
    }

    fn generateServerKey(allocator: Allocator, client_key: []const u8) ![]const u8 {
        const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        const encoder = std.base64.Base64Encoder.init(std.base64.standard_alphabet_chars, '=');
        var sha1 = std.crypto.hash.Sha1.init(.{});

        const key_magic = try std.mem.concat(allocator, u8, &.{ client_key, magic });
        defer allocator.free(key_magic);

        sha1.update(key_magic);
        const sha1_result = sha1.finalResult();

        const encode_size = encoder.calcSize(sha1_result.len);
        const base64_result = try allocator.alloc(u8, encode_size);
        return encoder.encode(base64_result, &sha1_result);
    }

    inline fn getSwitchingProtocolsResponse() []const u8 {
        return "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n" ++
            "\r\n";
    }

    fn getConnection(server: *Server) ?Connection {
        return server.accept() catch {
            std.debug.print("Server did not accept the response\n", .{});
            return null;
        };
    }

    fn readFromConnection(websocket: *WebSocketInstance, buffer: []u8) ?usize {
        const length = websocket.connection.stream.read(buffer) catch return null;
        return if (length > 0) length else null;
    }
};

pub const WebSocketInstance = struct {
    allocator: Allocator,
    connection: Connection,
    server: *std.http.Server,
    lastReadTime: i64,

    const Self = @This();

    pub fn init(allocator: Allocator, connection: Connection) !WebSocketInstance {
        const reader_buffer: []u8 = try allocator.alloc(u8, std.heap.pageSize());
        var stream_reader = connection.stream.reader(reader_buffer);

        const writer_buffer: []u8 = try allocator.alloc(u8, std.heap.pageSize());
        var stream_writer = connection.stream.writer(writer_buffer);

        var server = std.http.Server.init(stream_reader.interface(), &stream_writer.interface);

        return .{
            .allocator = allocator,
            .connection = connection,
            .server = &server,
            .lastReadTime = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(websocket: *Self) void {
        websocket.connection.stream.close();
    }

    pub fn websocketRead(websocket: *Self, buffer: []u8) !?[]const u8 {
        const message_length = try websocket.connection.stream.read(buffer);
        if (message_length > 0) websocket.lastReadTime = std.time.milliTimestamp();
        var seek: usize = 0;

        if (parseFrame(&seek, buffer)) |frame| {
            std.debug.print("{s}\n", .{frame});
            return frame;
        }

        return null;
    }

    fn parseFrame(seek: *usize, buffer: []u8) ?[]const u8 {
        const fin = (buffer[seek.*] & 0x80) != 0;
        const opcode = buffer[seek.*] & 0x0F;
        seek.* += 1;

        const is_masked = (buffer[seek.*] & 0x80) != 0;
        var payload_len: usize = buffer[seek.*] & 0x7F;
        seek.* += 1;

        if (!fin) {
            std.debug.print("Fragmenting messages not supported\n", .{});
            return null;
        }

        if (opcode == @intFromEnum(OpcodeValue.Pong)) {
            std.debug.print("Detected heartbeat. Keep connection live\n", .{});
            return &.{};
        } else if (opcode != @intFromEnum(OpcodeValue.Message)) {
            std.debug.print("Only text is valid for messages\n", .{});
            return null;
        }

        if (payload_len == 126) {
            const current_byte: usize = buffer[seek.*];
            const next_byte: usize = buffer[seek.* + 1];
            payload_len = (current_byte << 8) + next_byte;
            seek.* += 2;
        } else if (payload_len == 127) {
            payload_len = 0;
            for (0..8) |i| {
                const current_byte: usize = buffer[i + seek.*];
                const offset_byte: u6 = @intCast((7 - i) * 8);
                payload_len += current_byte << offset_byte;
            }

            seek.* += 8;
        }

        if (is_masked) {
            const mask_key = buffer[seek.* .. seek.* + 4];
            seek.* += 4;

            for (0..payload_len) |i| {
                const payload_index = seek.* + i;
                buffer[payload_index] = buffer[payload_index] ^ mask_key[i % 4];
            }
        }

        const frame = buffer[seek.* .. seek.* + payload_len];
        seek.* += payload_len;

        return frame;
    }

    pub fn websocketMessage(websocket: *Self, payload: []const u8) !void {
        var buffer: [4096]u8 = undefined;
        var seek: usize = 0;
        createFrame(&seek, &buffer, payload, .Message);
        _ = try websocket.connection.stream.write(buffer[0..seek]);
    }

    fn websocketHeartbeatCheck(websocket: *Self) !void {
        var buffer: [2]u8 = undefined;
        var seek: usize = 0;
        createFrame(&seek, &buffer, &.{}, .Ping);
        _ = try websocket.connection.stream.write(buffer[0..seek]);
    }

    fn websocketReadPong(websocket: *Self) !void {
        var buffer: [2]u8 = undefined;
        _ = try websocket.connection.stream.read(&buffer);
        var seek: usize = 0;
        if (parseFrame(&seek, &buffer) != null)
            websocket.lastReadTime = std.time.milliTimestamp();
    }

    fn createFrame(seek: *usize, buffer: []u8, payload: []const u8, opcode: OpcodeValue) void {
        const fin: u8 = 0x80;
        const payload_bits: u8 = payload_blk: {
            if (payload.len <= 125) {
                break :payload_blk @intCast(payload.len);
            } else if (payload.len <= 0xFFFF) {
                break :payload_blk 126;
            } else {
                break :payload_blk 127;
            }
        };

        buffer[seek.*] = fin + @intFromEnum(opcode);
        seek.* += 1;

        buffer[seek.*] = payload_bits;
        seek.* += 1;

        switch (payload_bits) {
            126 => {
                buffer[seek.*] = @intCast((payload.len >> 8) & 0xFF);
                buffer[seek.* + 1] = @intCast(payload.len & 0xFF);
                seek.* += 2;
            },
            127 => {
                for (0..8) |i| {
                    const current_byte: usize = seek.* + i;
                    const offset_byte: u6 = @intCast((7 - i) * 8);
                    buffer[current_byte] = @intCast((payload.len >> offset_byte) & 0xFF);
                }

                seek.* += 8;
            },
            else => {},
        }

        for (0..payload.len) |i|
            buffer[seek.* + i] = payload[i];

        seek.* += payload.len;
    }

    fn heartbeatTimer(websocket: *Self) error{ HeartbeatFailed, HeartbeatLost }!void {
        if (websocket.lastReadTime < std.time.milliTimestamp() - 5 * std.time.ms_per_s) {
            std.debug.print("Sent ping", .{});
            websocketHeartbeatCheck(websocket) catch {
                std.debug.print("Heartbeat ping failed. Closing connection\n", .{});
                return error.HeartbeatFailed;
            };

            if (websocket.lastReadTime < std.time.milliTimestamp() - 10 * std.time.ms_per_s) {
                websocketReadPong(websocket) catch {
                    std.debug.print("Heartbeat pong failed. Closing connection\n", .{});
                    return error.HeartbeatFailed;
                };
            } else return error.HeartbeatLost; // Automatically disconnect the connection
        }
    }
};
