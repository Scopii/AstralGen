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
    defer windowMan.deinit();

    var renderer = try Renderer.init(&memoryMan);
    defer renderer.deinit();

    try windowMan.addWindow("Astral1", 1600, 900, .compute);
    try windowMan.addWindow("Astral2", 16 * 70, 9 * 70, .graphics);
    try windowMan.addWindow("Astral3", 350, 350, .mesh);

    const win1: f32 = 3.333;
    const win2: f32 = 1.234;
    const win3: f32 = 6.666;

    std.debug.print("\n", .{});

    const TestMapArray = CreateMapArray(f64, 2, u32, 10, 0);
    std.debug.print("NewArray Size: {} bytes\n", .{@sizeOf(TestMapArray)});
    var mapArray2: TestMapArray = .{};
    mapArray2.set(8, win1);
    mapArray2.set(8, win2);
    mapArray2.set(1, win3);

    mapArray2.set(1, win2);

    var element: f64 = 0;
    std.debug.print("Size {}", .{@sizeOf(u8)});

    const time1 = std.time.milliTimestamp();

    for (0..1_000) |_| {
        element += mapArray2.get(1);
        mapArray2.set(1, element);
    }
    const time2 = std.time.milliTimestamp();

    var hashTestMap = std.AutoHashMap(u32, f64).init(memoryMan.allocator);
    defer hashTestMap.deinit();
    try hashTestMap.put(1, win2);
    element = 0;

    const time3 = std.time.milliTimestamp();

    for (0..1_000) |_| {
        element += hashTestMap.get(1).?;
        const ptr = hashTestMap.getPtr(1).?;
        ptr.* = element;
    }
    const time4 = std.time.milliTimestamp();

    std.debug.print("\n", .{});
    std.debug.print("Time MapArray {}ms\n", .{time2 - time1});
    std.debug.print("Time HashMap {}ms\n", .{time4 - time3});

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
