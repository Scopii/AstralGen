// Imports
const std = @import("std");
const WindowManager = @import("platform/WindowManager.zig").WindowManager;
const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const Renderer = @import("engine/Renderer.zig").Renderer;
const Window = @import("platform/Window.zig").Window;
const zjobs = @import("zjobs");

const DEBUG_CLOSE = @import("settings.zig").DEBUG_CLOSE;

// Re-Formats
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var debugAlloc = std.heap.DebugAllocator(.{}).init;
    defer std.debug.print("Memory: {any}\n", .{debugAlloc.deinit()});
    var memoryMan = try MemoryManager.init(debugAlloc.allocator());
    defer memoryMan.deinit();

    var windowMan = try WindowManager.init(&memoryMan);
    defer windowMan.deinit();

    var renderer = try Renderer.init(&memoryMan);
    defer renderer.deinit();

    try windowMan.addWindow("Astral1", &renderer, 1600, 900, .compute);
    try windowMan.addWindow("Astral2", &renderer, 16 * 70, 9 * 70, .graphics);
    try windowMan.addWindow("Astral3", &renderer, 350, 350, .mesh);

    // Main loop
    while (true) {
        try windowMan.pollEvents(&renderer);
        if (windowMan.close == true) return;
        if (windowMan.openWindows == 0) continue;

        const swapchainsToDraw = try windowMan.getSwapchainsToDraw();
        try renderer.updateRenderImage(swapchainsToDraw);
        try renderer.draw(swapchainsToDraw);
        memoryMan.resetArena();
    }

    std.debug.print("App Closed\n", .{});

    if (DEBUG_CLOSE == true) {
        const stdout = std.io.getStdOut().writer();
        _ = try stdout.write("Press Enter to exit...\n");
        _ = std.io.getStdIn().reader().readByte() catch {};
    }
}
