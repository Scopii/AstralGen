// Imports
const std = @import("std");
const WindowManager = @import("platform/WindowManager.zig").WindowManager;
const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const CreateMapArray = @import("structures/MapArray.zig").CreateMapArray;
const Renderer = @import("vulkan/Renderer.zig").Renderer;
const EventManager = @import("core/EventManager.zig").EventManager;
const Window = @import("platform/Window.zig").Window;
const zjobs = @import("zjobs");
const CLOSE_WITH_CONSOLE = @import("config.zig").CLOSE_WITH_CONSOLE;
// Re-Formats
const Allocator = std.mem.Allocator;

pub fn main() !void {
    defer {
        if (CLOSE_WITH_CONSOLE) {
            std.debug.print("Press Any Key to exit...\n", .{});
            _ = std.io.getStdIn().reader().readByte() catch {};
        }
    }

    var debugAlloc = std.heap.DebugAllocator(.{}).init;
    defer std.debug.print("Memory: {any}\n", .{debugAlloc.deinit()});
    var memoryMan = try MemoryManager.init(debugAlloc.allocator());
    defer memoryMan.deinit();

    var eventMan: EventManager = .{};

    var windowMan = try WindowManager.init();
    defer windowMan.deinit();

    var renderer = Renderer.init(&memoryMan) catch |err| {
        windowMan.showErrorBox("Renderer Could not launch", "Your GPU might not support Mesh Shaders.\n");
        std.debug.print("Error {}\n", .{err});
        return;
    };
    defer renderer.deinit();

    try windowMan.addWindow("Astral1", 1600, 900, .compute);
    try windowMan.addWindow("Astral2", 16 * 70, 9 * 70, .graphics);
    try windowMan.addWindow("Astral3", 350, 350, .mesh);

    // Main loop
    while (true) {
        windowMan.pollEvents() catch |err| {
            std.log.err("Error in pollEvents(): {}", .{err});
            break;
        };

        if (windowMan.keyEvents.len > 0) {
            eventMan.mapKeyEvents(windowMan.consumeKeyEvents());

            for (eventMan.getAppEvents()) |appEvent| {
                switch (appEvent) {
                    .updateCam => {},
                    .closeApp => return,
                    .restartApp => {},
                }
            }
            eventMan.cleanupAppEvents();
        }

        if (windowMan.changedWindows.len > 0) {
            try renderer.update(windowMan.changedWindows.slice());
            try windowMan.cleanupWindows();
        }

        if (windowMan.close == true) return;
        if (windowMan.openWindows == 0) continue;

        renderer.draw() catch |err| {
            std.log.err("Error in renderer.draw(): {}", .{err});
            break;
        };
        memoryMan.resetArena();
    }
    std.debug.print("App Closed\n", .{});
}
