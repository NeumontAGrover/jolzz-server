const std = @import("std");

const WebSocketInstance = @import("jolzz_server.zig").WebSocketInstance;

pub const PlayerColor = enum { White, Black, None };

pub const Player = struct {
    allocator: std.mem.Allocator,
    websocket: *WebSocketInstance,
    color: PlayerColor,
    username: ?[]u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, websocket: *WebSocketInstance) !*Self {
        var player = try allocator.create(Self);
        player.allocator = allocator;
        player.color = .None;
        player.websocket = websocket;
        player.username = null;
        return player;
    }

    pub fn deinit(self: *Self) void {
        self.websocket.deinit();
        self.allocator.free(self.username.?);
        self.allocator.destroy(self);
    }

    pub fn setUsername(self: *Self, username: []const u8) void {
        self.username = self.allocator.alloc(u8, username.len) catch @panic("OOM");
        @memcpy(self.username.?, username);
        std.debug.print("username: {s}\n", .{self.username.?});
    }
};
