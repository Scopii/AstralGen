const CLOSE_WITH_CONSOLE = @import("configs/appConfig.zig").CLOSE_WITH_CONSOLE;
const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const App = @import("App.zig").App;
const std = @import("std");

pub fn main() void {
    std.debug.print("AstralGen Started\n", .{});
    defer {
        if (CLOSE_WITH_CONSOLE == true) {
            std.debug.print("Press Enter to exit...\n", .{});
            var buf: [1]u8 = undefined;
            _ = std.fs.File.stdin().read(&buf) catch {};
        }
    }
    // Memory Setup
    var debugAlloc = std.heap.DebugAllocator(.{}).init;
    defer std.debug.print("Memory: {any}\n", .{debugAlloc.deinit()});
    var memoryMan = MemoryManager.init(debugAlloc.allocator());
    defer memoryMan.deinit();

    // Application Setup
    var astralGen = App.init(&memoryMan) catch |err| {
        std.debug.print("AstralGen failed to launch Err {}\n", .{err});
        return;
    };
    defer astralGen.deinit();

    astralGen.initWindows() catch |err| {
        std.debug.print("AstralGen failed to init Windows Err {}\n", .{err});
        return;
    };

    astralGen.run() catch |err| {
        std.debug.print("AstralGen failed while running Err {}\n", .{err});
        return;
    };

    std.debug.print("AstralGen Closed\n", .{});
}
