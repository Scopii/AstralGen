// Imports
const std = @import("std");
const App = @import("core/app.zig").App;
const Renderer = @import("engine/renderer.zig").Renderer;
// Re-Formats
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var app = try App.init();
    defer app.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.log.debug("Memory check : {any}\n", .{gpa.deinit()});
    const alloc = gpa.allocator();

    var renderer = try Renderer.init(alloc, app.window, &app.extent);
    defer renderer.deinit();

    // main loop
    while (app.close == false) {
        app.pollEvents();
        try renderer.draw();
    }
}
