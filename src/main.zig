// Imports
const std = @import("std");
const App = @import("core/App.zig").App;
const Renderer = @import("engine/Renderer.zig").Renderer;
const zjobs = @import("zjobs");

// Re-Formats
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var app = try App.init(1600, 900);
    defer app.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.print("Memory: {any}\n", .{gpa.deinit()});
    const alloc = gpa.allocator();

    var renderer = try Renderer.init(alloc, app.window, app.extent);
    defer renderer.deinit();

    // main loop
    while (app.close == false) {
        app.handle();
        app.pollEvents();
        try renderer.draw(.compute);
    }

    //const stdout = std.io.getStdOut().writer();
    //_ = try stdout.write("Press Enter to exit...\n");
    //_ = std.io.getStdIn().reader().readByte() catch {};
}
