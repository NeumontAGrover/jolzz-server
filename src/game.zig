const std = @import("std");
const Player = @import("player.zig").Player;
const PlayerColor = @import("player.zig").PlayerColor;

const GameActionType = enum { WhiteMove, BlackMove, GameEnd, Invalid };

pub const Game = struct {
    turn: PlayerColor,
    white_player: ?*Player,
    black_player: ?*Player,

    const Self = @This();

    pub fn init() Self {
        return .{
            .turn = .White,
            .white_player = null,
            .black_player = null,
        };
    }

    pub fn getGameMessage(self: *Self, message: []const u8) void {
        const action = parseGameMessage(message);
        switch (action) {
            .WhiteMove => {
                if (self.turn == .White) return;
            },
            .BlackMove => {
                if (self.turn == .Black) return;
            },
            .GameEnd => {},
            .Invalid => return,
        }
    }

    fn parseGameMessage(message: []const u8) GameActionType {
        return switch (message[0]) {
            't' => switch (message[1]) {
                'w' => .WhiteMove,
                'b' => .BlackMove,
                else => .Invalid,
            },
            'e' => .GameEnd,
            else => .Invalid,
        };
    }

    pub fn addPlayer(self: *Self, new_player: *Player) void {
        if (self.isEmpty()) {
            const random_side = std.Random.boolean(std.Random.DefaultPrng);
            if (random_side) {
                self.white_player = new_player;
            } else self.black_player = new_player;
        } else {
            if (self.white_player == null) {
                self.white_player = new_player;
            } else self.black_player = new_player;
        }
    }

    pub fn flipTurn(self: *Self) void {
        if (self.turn == .White) {
            self.turn = .Black;
        } else self.turn = .White;
    }

    pub fn isEmpty(self: *Self) bool {
        return self.white_player == null and self.black_player == null;
    }

    pub fn isFull(self: *Self) bool {
        return self.white_player != null and self.black_player != null;
    }
};
