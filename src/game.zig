const std = @import("std");
const Player = @import("player.zig").Player;
const PlayerColor = @import("player.zig").PlayerColor;

const GameActionType = enum { WhiteMove, BlackMove, WhiteWin, BlackWin, Invalid };

pub const Game = struct {
    allocator: std.mem.Allocator,
    turn: PlayerColor,
    white_player: ?*Player,
    black_player: ?*Player,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        var game = try allocator.create(Self);
        game.allocator = allocator;
        game.turn = .White;
        game.white_player = null;
        game.black_player = null;
        return game;
    }

    pub fn deinit(self: *Self) void {
        if (self.white_player) |player| player.deinit();
        if (self.black_player) |player| player.deinit();
        self.allocator.destroy(self);
    }

    pub fn getGameMessage(self: *Self, player: *const Player, message: []const u8) void {
        if (!self.isFull()) {
            std.debug.print("game is not full\n", .{});
            return;
        }

        if (player.color != self.turn) {
            std.debug.print("{any} cannot play. {any} is playing\n", .{ player.color, self.turn });
            return;
        }

        const action = parseGameMessage(message);
        switch (action) {
            .WhiteMove => {
                if (player.color == .Black) {
                    std.debug.print("Cannot move white as black\n", .{});
                    return;
                }

                if (self.turn == .Black) {
                    std.debug.print("Cannot move white\n", .{});
                    return;
                }

                std.debug.print("Moved white\n", .{});
            },
            .BlackMove => {
                if (player.color == .White) {
                    std.debug.print("Cannot move black as white\n", .{});
                    return;
                }

                if (self.turn == .White) {
                    std.debug.print("Cannot move black\n", .{});
                    return;
                }

                std.debug.print("Moved black\n", .{});
            },
            .WhiteWin => {},
            .BlackWin => {},
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
            'e' => switch (message[1]) {
                'w' => .WhiteWin,
                'b' => .BlackWin,
                else => .Invalid,
            },
            else => .Invalid,
        };
    }

    pub fn addPlayer(self: *Self, new_player: *Player) !void {
        if (self.isEmpty()) {
            std.debug.print("putting player on random side\n", .{});
            const seed: u64 = @intCast(std.time.milliTimestamp());
            var xoshiro256 = std.Random.DefaultPrng.init(seed);
            const is_white_side = std.Random.boolean(xoshiro256.random());
            if (is_white_side) {
                new_player.color = .White;
                self.white_player = new_player;
                std.debug.print("Added white player\n", .{});
            } else {
                new_player.color = .Black;
                self.black_player = new_player;
                std.debug.print("Added black player\n", .{});
            }
        } else {
            if (self.white_player == null) {
                new_player.color = .White;
                self.white_player = new_player;
                std.debug.print("Added white player\n", .{});
            } else {
                new_player.color = .Black;
                self.black_player = new_player;
                std.debug.print("Added black player\n", .{});
            }
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
        std.debug.print("players: {} ", .{self.white_player != null});
        std.debug.print("{}\n", .{self.black_player != null});
        return self.white_player != null and self.black_player != null;
    }
};
