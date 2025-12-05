const std = @import("std");

const WebSocketInstance = @import("jolzz_server.zig").WebSocketInstance;

pub const PlayerColor = enum { White, Black, None };

pub const Player = struct {
    allocator: std.mem.Allocator,
    websocket: *WebSocketInstance,
    color: PlayerColor,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, websocket: *WebSocketInstance) !*Self {
        var player = try allocator.create(Self);
        player.allocator = allocator;
        player.color = .None;
        player.websocket = websocket;
        return player;
    }

    pub fn deinit(self: *Self) void {
        self.websocket.deinit();
        self.allocator.destroy(self);
    }
};
