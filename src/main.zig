// Imports
const std = @import("std");
const WindowManager = @import("platform/WindowManager.zig").WindowManager;
const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const CreateMapArray = @import("structures/MapArray.zig").CreateMapArray;
const Renderer = @import("vulkan/Renderer.zig").Renderer;
const Window = @import("platform/Window.zig").Window;
const zjobs = @import("zjobs");
const DEBUG_CLOSE = @import("config.zig").DEBUG_CLOSE;
// Re-Formats
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var debugAlloc = std.heap.DebugAllocator(.{}).init;
    defer std.debug.print("Memory: {any}\n", .{debugAlloc.deinit()});
    var memoryMan = try MemoryManager.init(debugAlloc.allocator());
    defer memoryMan.deinit();

    var windowMan = try WindowManager.init(&memoryMan);
    defer windowMan.deinit() catch {
        std.debug.print("could not cleanup windowMan", .{});
    };

    var renderer = try Renderer.init(&memoryMan);
    defer renderer.deinit();

    try windowMan.addWindow("Astral1", 1600, 900, .compute);
    try windowMan.addWindow("Astral2", 16 * 70, 9 * 70, .graphics);
    try windowMan.addWindow("Astral3", 350, 350, .mesh);

    const win1: f32 = 3.333;
    const win2: f32 = 1.234;
    const win3: f32 = 6.666;

    const WinMapArray = CreateMapArray(f32, u6, 18);
    var mapArray: WinMapArray = .{};
    mapArray.printAll();
    std.debug.print("\nMap Array count {}\n", .{mapArray.getCount()});
    try mapArray.addWithKey(4, win1);
    mapArray.printAll();

    try mapArray.addWithKey(6, win2);
    mapArray.printAll();

    try mapArray.addWithKey(8, win3);
    mapArray.printAll();
    std.debug.print("Map Array count {}\n", .{mapArray.getCount()});

    try mapArray.addWithKey(62, win3);
    std.debug.print("Map Array Sentinel {}\n", .{mapArray.getSentinel()});
    std.debug.print("Map Array Last Key {}\n", .{mapArray.getLastKey()});
    mapArray.printAll();

    // std.debug.print("Map Array Key 4 = {}\n", .{try mapArray.getFromKey(4)});
    // std.debug.print("Map Array Spot 4 = {}\n", .{try mapArray.getAtIndex(3)});
    // std.debug.print("Map Array Size = {}\n", .{mapArray.size});
    std.debug.print("Map Array Size in Bytes {}\n", .{@sizeOf(WinMapArray)});

    // std.debug.print("?u8: {} bytes\n", .{@sizeOf(?u8)});
    // std.debug.print("?u32: {} bytes\n", .{@sizeOf(?u32)});
    // std.debug.print("?usize: {} bytes\n", .{@sizeOf(?usize)});

    std.debug.print("\n", .{});

    // Main loop
    while (true) {
        windowMan.pollEvents() catch |err| {
            std.log.err("Error in pollEvents(): {}", .{err});
            break;
        };

        if (windowMan.swapchainsToChange.items.len > 0) {
            try renderer.update(windowMan.swapchainsToChange.items, try windowMan.getSwapchainsToDraw2());
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

    if (DEBUG_CLOSE == true) {
        const stdout = std.io.getStdOut().writer();
        _ = try stdout.write("Press Enter to exit...\n");
        _ = std.io.getStdIn().reader().readByte() catch {};
    }
}
