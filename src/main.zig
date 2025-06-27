// Imports
const std = @import("std");
const WindowManager = @import("core/WindowManager.zig").WindowManager;
const Renderer = @import("engine/Renderer.zig").Renderer;
const zjobs = @import("zjobs");

const DEBUG_TOGGLE = @import("settings.zig").DEBUG_TOGGLE;

// Re-Formats
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.print("Memory: {any}\n", .{gpa.deinit()});
    const alloc = gpa.allocator();

    var windowMan = try WindowManager.init(alloc);
    defer windowMan.deinit();
    try windowMan.createWindow("AstralGen", 1600, 900);

    const window = try windowMan.getWindow(4);
    var renderer = try Renderer.init(alloc, window.handle, window.extent);
    defer renderer.deinit();

    // main loop
    while (windowMan.close == false) {
        try windowMan.pollEvents(&renderer);

        if (windowMan.paused == false) {
            try renderer.draw(.mesh);
        }
    }

    if (DEBUG_TOGGLE == true) {
        //const stdout = std.io.getStdOut().writer();
        //_ = try stdout.write("Press Enter to exit...\n");
        //_ = std.io.getStdIn().reader().readByte() catch {};
    }
}
