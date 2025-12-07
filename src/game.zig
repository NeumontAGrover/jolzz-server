const std = @import("std");
const Player = @import("player.zig").Player;
const PlayerColor = @import("player.zig").PlayerColor;

const GameAction = enum {
    WhiteMove,
    BlackMove,
    WhiteWin,
    BlackWin,
    SetUsername,
    Invalid,
};

const Piece = *const [2:0]u8;

pub const Game = struct {
    allocator: std.mem.Allocator,
    turn: PlayerColor,
    white_player: ?*Player,
    black_player: ?*Player,
    started: bool,
    board: [64]Piece = undefined,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        var game = try allocator.create(Self);
        game.allocator = allocator;
        game.turn = .White;
        game.white_player = null;
        game.black_player = null;
        game.started = false;
        game.generateBoard();
        return game;
    }

    pub fn deinit(self: *Self) void {
        if (self.white_player) |player| player.deinit();
        if (self.black_player) |player| player.deinit();
        self.allocator.destroy(self);
    }

    pub fn getGameMessage(self: *Self, player: *Player, message: []const u8) void {
        const action = parseGameMessage(message);
        switch (action) {
            .WhiteMove => {
                if (player.username == null) {
                    sendMessageToPlayer(player, "user_authenticated=false");
                    return;
                }

                if (self.canPlayerMove(player, .White)) {
                    sendMessageToPlayer(player, "valid_move=true");
                    sendMessageToPlayer(self.black_player.?, message[3..]);
                } else sendMessageToPlayer(player, "valid_move=false");
            },
            .BlackMove => {
                if (player.username == null) {
                    sendMessageToPlayer(player, "user_authenticated=false");
                    return;
                }

                if (self.canPlayerMove(player, .Black)) {
                    sendMessageToPlayer(player, "valid_move=true");
                    sendMessageToPlayer(self.white_player.?, message[3..]);
                } else sendMessageToPlayer(player, "valid_move=false");
            },
            .WhiteWin => {},
            .BlackWin => {},
            .SetUsername => {
                player.setUsername(message[2..]);
                sendMessageToPlayer(player, "user_authenticated=true");
            },
            .Invalid => return,
        }
    }

    fn parseGameMessage(message: []const u8) GameAction {
        if (message.len == 0) return .Invalid;

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
            'u' => .SetUsername,
            else => .Invalid,
        };
    }

    fn sendMessageToPlayer(player: *const Player, message: []const u8) void {
        player.websocket.websocketMessage(message) catch |err|
            std.debug.print("Could not send message ({any})\n", .{err});
    }

    fn canPlayerMove(self: *const Self, player: *const Player, side_moving: PlayerColor) bool {
        return !self.isFull() or side_moving != self.turn or player.color != side_moving;
    }

    pub fn addPlayer(self: *Self, new_player: *Player) !void {
        if (self.isEmpty()) {
            const seed: u64 = @intCast(std.time.milliTimestamp());
            var xoshiro256 = std.Random.DefaultPrng.init(seed);
            const is_white_side = std.Random.boolean(xoshiro256.random());
            if (is_white_side) {
                new_player.color = .White;
                self.white_player = new_player;
            } else {
                new_player.color = .Black;
                self.black_player = new_player;
            }
        } else {
            if (self.white_player == null) {
                new_player.color = .White;
                self.white_player = new_player;
            } else {
                new_player.color = .Black;
                self.black_player = new_player;
            }
        }
    }

    pub fn removePlayer(self: *Self, color: PlayerColor) void {
        if (color == .White and self.white_player != null) {
            self.white_player.?.deinit();
            self.white_player = null;
        } else if (color == .Black and self.black_player != null) {
            self.black_player.?.deinit();
            self.black_player = null;
        }
    }

    pub fn sendGameIsReady(self: *Self) void {
        var players_invalid = false;
        if (self.white_player.?.username == null) {
            std.debug.print("white player invalid\n", .{});
            sendMessageToPlayer(self.white_player.?, "user_authenticated=false");
            players_invalid = true;
        }

        if (self.black_player.?.username == null) {
            std.debug.print("black player invalid\n", .{});
            sendMessageToPlayer(self.black_player.?, "user_authenticated=false");
            players_invalid = true;
        }

        if (players_invalid) return;

        std.debug.print("\x1b[1;30;42m\nGame is ready\x1b[0m\n", .{});
        std.debug.print("\x1b[34m{s} (white)\n", .{self.white_player.?.username.?});
        std.debug.print("{s} (black)\x1b[0m\n", .{self.black_player.?.username.?});

        const game_ready_message_white = std.mem.concat(
            self.allocator,
            u8,
            &.{ "game_ready=true,", self.black_player.?.username.? },
        ) catch @panic("OOM");
        defer self.allocator.free(game_ready_message_white);
        sendMessageToPlayer(self.white_player.?, game_ready_message_white);
        // sendMessageToPlayer(self.white_player.?, self.boardString());

        const game_ready_message_black = std.mem.concat(
            self.allocator,
            u8,
            &.{ "game_ready=true,", self.white_player.?.username.? },
        ) catch @panic("OOM");
        defer self.allocator.free(game_ready_message_black);
        sendMessageToPlayer(self.black_player.?, game_ready_message_black);
        // sendMessageToPlayer(self.black_player.?, self.boardString());

        self.started = true;
    }

    fn generateBoard(self: *Self) void {
        const seed: u64 = @intCast(std.time.milliTimestamp());
        var xoshiro256 = std.Random.DefaultPrng.init(seed);
        const random = xoshiro256.random();

        const white_rows = [_]u8{ 0, 16 };
        const black_rows = [_]u8{ 48, 64 };
        var created_pieces: [16]Piece = undefined;

        const king_placement = random.intRangeAtMost(u3, 0, 7);
        self.board[king_placement] = "wk";
        created_pieces[king_placement] = "wk";

        for (white_rows[0]..white_rows[1]) |i| {
            if (king_placement == i) continue;

            switch (random.intRangeAtMost(u3, 0, 4)) {
                0 => self.board[i] = "wp",
                1 => self.board[i] = "wb",
                2 => self.board[i] = "wn",
                3 => self.board[i] = "wr",
                4 => self.board[i] = "wq",
                else => @panic("Invalid piece"),
            }

            created_pieces[i] = self.board[i];
        }

        for (black_rows[0]..black_rows[1]) |i| {
            const loop_index = i - black_rows[0];
            const row = loop_index / 8;
            self.board[i] = created_pieces[(loop_index % 8) + (1 - row) * 8];
            self.board[i] = switch (self.board[i][1]) {
                'p' => "bp",
                'b' => "bb",
                'n' => "bn",
                'r' => "br",
                'q' => "bq",
                'k' => "bk",
                else => @panic("Invalid Piece"),
            };
        }

        for (white_rows[1]..black_rows[0]) |i|
            self.board[i] = "__";
    }

    fn boardString(self: *Self) []const u8 {
        var board_string: [self.board.len * 2]u8 = undefined;
        for (0..self.board.len) |i| {
            const piece = self.board[i];
            board_string[i * 2] = piece[0];
            board_string[i * 2 + 1] = piece[1];
        }

        return &board_string;
    }

    pub fn isReady(self: *const Self) bool {
        return !self.started and self.isFull();
    }

    pub fn flipTurn(self: *Self) void {
        if (self.turn == .White) {
            self.turn = .Black;
        } else self.turn = .White;
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.white_player == null and self.black_player == null;
    }

    pub fn isFull(self: *const Self) bool {
        return self.white_player != null and self.black_player != null;
    }
};

test "Create Chess Board" {
    var board: [64]Piece = undefined;

    const seed: u64 = @intCast(std.time.milliTimestamp());
    var xoshiro256 = std.Random.DefaultPrng.init(seed);
    const random = xoshiro256.random();

    const white_rows = [_]u8{ 0, 16 };
    const black_rows = [_]u8{ 48, 64 };
    var created_pieces: [16]Piece = undefined;

    const king_placement = random.intRangeAtMost(u3, 0, 7);
    board[king_placement] = "wk";
    created_pieces[king_placement] = "wk";

    for (white_rows[0]..white_rows[1]) |i| {
        if (king_placement == i) continue;

        switch (random.intRangeAtMost(u3, 0, 4)) {
            0 => board[i] = "wp",
            1 => board[i] = "wb",
            2 => board[i] = "wn",
            3 => board[i] = "wr",
            4 => board[i] = "wq",
            else => @panic("Invalid piece"),
        }

        created_pieces[i] = board[i];
    }

    for (black_rows[0]..black_rows[1]) |i| {
        const loop_index = i - black_rows[0];
        const row = loop_index / 8;
        board[i] = created_pieces[(loop_index % 8) + (1 - row) * 8];
        board[i] = switch (board[i][1]) {
            'p' => "bp",
            'b' => "bb",
            'n' => "bn",
            'r' => "br",
            'q' => "bq",
            'k' => "bk",
            else => @panic("Invalid Piece"),
        };
    }

    for (white_rows[1]..black_rows[0]) |i|
        board[i] = "__";

    for (board, 0..) |piece, i| {
        if (i % 8 == 0) std.debug.print("\n", .{});
        std.debug.print(" {s} ", .{piece});
    }
    std.debug.print("\n", .{});

    var board_string: [board.len * 2]u8 = undefined;
    for (0..board.len) |i| {
        const piece = board[i];
        board_string[i * 2] = piece[0];
        board_string[i * 2 + 1] = piece[1];
    }
    std.debug.print("{s}\n", .{board_string});
}
