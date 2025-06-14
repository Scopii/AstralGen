// Imports
const std = @import("std");
const App = @import("core/app.zig").App;
const Renderer = @import("engine/renderer.zig").Renderer;
const zjobs = @import("zjobs");

// Re-Formats
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var app = try App.init();
    defer app.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.print("Memory: {any}\n", .{gpa.deinit()});
    const alloc = gpa.allocator();

    var renderer = try Renderer.init(alloc, app.window, &app.extent);
    defer renderer.deinit();

    // main loop
    while (app.close == false) {
        app.handle();
        app.pollEvents();

        //try renderer.draw();
        try renderer.drawComputeRenderer();
    }
}
