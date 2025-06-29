// Imports
const std = @import("std");
const WindowManager = @import("core/WindowManager.zig").WindowManager;
const Renderer = @import("engine/Renderer.zig").Renderer;
const zjobs = @import("zjobs");

const DEBUG_CLOSE = @import("settings.zig").DEBUG_CLOSE;

// Re-Formats
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.print("Memory: {any}\n", .{gpa.deinit()});
    const alloc = gpa.allocator();

    var windowMan = try WindowManager.init(alloc);
    defer windowMan.deinit();

    try windowMan.createWindow("AstralGen", 1600, 900, .compute);
    var window1 = try windowMan.getWindow(4);

    var renderer = try Renderer.init(alloc, &window1);
    defer renderer.deinit();

    try windowMan.createWindow("AstralGen1", 1280, 720, .graphics);
    var window2 = try windowMan.getWindow(5);
    try renderer.addWindow(&window2);
    try windowMan.createWindow("AstralGen2", 800, 800, .mesh);
    var window3 = try windowMan.getWindow(6);
    try renderer.addWindow(&window3);

    // main loop
    while (true) {
        try windowMan.pollEvents(&renderer);
        if (windowMan.close == true) return;

        if (windowMan.paused == false) {
            try renderer.draw();
        }
    }

    std.debug.print("App Closed", .{});

    if (DEBUG_CLOSE == true) {
        const stdout = std.io.getStdOut().writer();
        _ = try stdout.write("Press Enter to exit...\n");
        _ = std.io.getStdIn().reader().readByte() catch {};
    }
}
