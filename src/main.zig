// Imports
const std = @import("std");
const WindowManager = @import("core/WindowManager.zig").WindowManager;
const Renderer = @import("engine/Renderer.zig").Renderer;
const VulkanWindow = @import("core/VulkanWindow.zig").VulkanWindow;
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

    var renderer = try Renderer.init(alloc);
    defer renderer.deinit();

    try windowMan.createWindow("AstralGen", 1600, 900, .compute);
    try windowMan.createWindow("AstralGen1", 1280, 720, .graphics);
    try windowMan.createWindow("AstralGen2", 800, 800, .mesh);

    try renderer.addWindow(windowMan.getWindowPtr(4).?);
    try renderer.addWindow(windowMan.getWindowPtr(5).?);
    try renderer.addWindow(windowMan.getWindowPtr(6).?);

    var windowsToDraw = std.ArrayList(*VulkanWindow).init(alloc);
    defer windowsToDraw.deinit();

    // main loop
    while (windowMan.close != true) {
        try windowMan.pollEvents(&renderer);

        if (windowMan.openWindows != 0) {
            try windowMan.fillWindowList(&windowsToDraw);
            try renderer.updateRenderImageSize(windowsToDraw.items);
            try renderer.draw(windowsToDraw.items);
        }
    }

    std.debug.print("App Closed\n", .{});

    if (DEBUG_CLOSE == true) {
        const stdout = std.io.getStdOut().writer();
        _ = try stdout.write("Press Enter to exit...\n");
        _ = std.io.getStdIn().reader().readByte() catch {};
    }
}
