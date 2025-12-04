const WebSocketInstance = @import("jolzz_server.zig").WebSocketInstance;

pub const PlayerColor = enum { White, Black };

pub const Player = struct {
    websocket: WebSocketInstance,
    color: PlayerColor,

    const Self = @This();

    pub fn init(color: PlayerColor, websocket: WebSocketInstance) Self {
        return .{ .color = color, .websocket = websocket };
    }
};
