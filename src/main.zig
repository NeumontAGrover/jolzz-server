const std = @import("std");
const JolzzServer = @import("jolzz_server.zig").JolzzServer;
const Game = @import("game.zig").Game;

const server_ip: []const u8 = "0.0.0.0";
const server_port: u16 = 3333;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer if (gpa.deinit() == .leak) @panic("Memory leaks detected");

    var current_games = try std.ArrayList(Game).initCapacity(allocator, 8);
    defer current_games.deinit(allocator);

    var jolzz_server = try JolzzServer.init(allocator, server_ip, server_port);
    defer jolzz_server.deinit();

    jolzz_server.connectionListener(&current_games);
}
