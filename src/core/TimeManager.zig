const std = @import("std");

pub const TimeManager = struct {
    pub const TimeUnit = enum { seconds, milli, micro, nano };
    // Set and used
    startup: i128,
    lastTime: i128,
    // Calculated
    runtime: i128 = 0,
    deltaTime: i128 = 0,

    pub fn init() TimeManager {
        const curentTime = std.time.nanoTimestamp();
        return .{
            .startup = curentTime,
            .lastTime = curentTime,
        };
    }

    pub fn update(self: *TimeManager) void {
        const newtime = std.time.nanoTimestamp();
        self.deltaTime = newtime - self.lastTime;
        self.lastTime = newtime;
        self.runtime = self.lastTime - self.startup;
    }

    pub fn convertTime(timeinNs: i128, unit: TimeUnit, comptime T: type) T {
        return switch (unit) {
            .seconds => if (@typeInfo(T) == .float) @as(T, @floatFromInt(timeinNs)) / 1_000_000_000 else @intCast(@divTrunc(timeinNs, 1_000_000_000)),
            .milli => if (@typeInfo(T) == .float) @as(T, @floatFromInt(timeinNs)) / 1_000_000 else @intCast(@divTrunc(timeinNs, 1_000_000)),
            .micro => if (@typeInfo(T) == .float) @as(T, @floatFromInt(timeinNs)) / 1_000 else @intCast(@divTrunc(timeinNs, 1_000)),
            .nano => if (@typeInfo(T) == .float) @as(T, @floatFromInt(timeinNs)) else @intCast(timeinNs),
        };
    }

    pub fn getStartup(self: *const TimeManager, unit: TimeUnit, comptime T: type) T {
        return convertTime(self.startup, unit, T);
    }

    pub fn getLastTime(self: *const TimeManager, unit: TimeUnit, comptime T: type) T {
        return convertTime(self.lastTime, unit, T);
    }

    pub fn getRuntime(self: *const TimeManager, unit: TimeUnit, comptime T: type) T {
        return convertTime(self.runtime, unit, T);
    }

    pub fn getDeltaTime(self: *const TimeManager, unit: TimeUnit, comptime T: type) T {
        return convertTime(self.deltaTime, unit, T);
    }

    pub fn printTimeInfo(self: *const TimeManager) void {
        std.debug.print("Startup as Float {d:.4}\n", .{self.getStartup(.seconds, f32)});
        std.debug.print("Startup as Int {}\n", .{self.getStartup(.seconds, u32)});
        std.debug.print("LastTime as Float {d:.4}\n", .{self.getLastTime(.seconds, f32)});
        std.debug.print("LastTime as Int {}\n", .{self.getLastTime(.seconds, u32)});
        std.debug.print("Runtime as Float {d:.4}\n", .{self.getRuntime(.seconds, f32)});
        std.debug.print("Runtime as Int {}\n", .{self.getStartup(.seconds, u32)});
        std.debug.print("DeltaTime as Float {d:.4}\n", .{self.getDeltaTime(.seconds, f32)});
        std.debug.print("DeltaTime as Int {}\n", .{self.getDeltaTime(.seconds, u32)});
    }
};
