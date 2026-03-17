const std = @import("std");
const TimeData = @import("../time/TimeData.zig").TimeData;

pub const TimeUnit = enum { seconds, milli, micro, nano };

pub const TimeSys = struct {
    pub fn init(timeState: *TimeData) void {
        const curTime = std.time.nanoTimestamp();
        timeState.startup = curTime;
        timeState.lastTime = curTime;
    }

    pub fn update(timeState: *TimeData) void {
        const newtime = std.time.nanoTimestamp();
        timeState.deltaTime = newtime - timeState.lastTime;
        timeState.lastTime = newtime;
        timeState.runtime = timeState.lastTime - timeState.startup;
    }

    pub fn convertTime(timeInNs: i128, unit: TimeUnit, comptime T: type) T {
        return switch (unit) {
            .seconds => if (@typeInfo(T) == .float) @as(T, @floatFromInt(timeInNs)) / 1_000_000_000 else @intCast(@divTrunc(timeInNs, 1_000_000_000)),
            .milli => if (@typeInfo(T) == .float) @as(T, @floatFromInt(timeInNs)) / 1_000_000 else @intCast(@divTrunc(timeInNs, 1_000_000)),
            .micro => if (@typeInfo(T) == .float) @as(T, @floatFromInt(timeInNs)) / 1_000 else @intCast(@divTrunc(timeInNs, 1_000)),
            .nano => if (@typeInfo(T) == .float) @as(T, @floatFromInt(timeInNs)) else @intCast(timeInNs),
        };
    }

    pub fn getStartup(timeState: *TimeData, unit: TimeUnit, comptime T: type) T {
        return convertTime(timeState.startup, unit, T);
    }

    pub fn getLastTime(timeState: *TimeData, unit: TimeUnit, comptime T: type) T {
        return convertTime(timeState.lastTime, unit, T);
    }

    pub fn getRuntime(timeState: *TimeData, unit: TimeUnit, comptime T: type) T {
        return convertTime(timeState.runtime, unit, T);
    }

    pub fn getDeltaTime(timeState: *TimeData, unit: TimeUnit, comptime T: type) T {
        return convertTime(timeState.deltaTime, unit, T);
    }

    pub fn printTimeInfo(timeState: *TimeData) void {
        std.debug.print("Startup as Float {d:.4}\n", .{getStartup(timeState, .seconds, f32)});
        std.debug.print("Startup as Int {}\n", .{getStartup(timeState, .seconds, u32)});
        std.debug.print("LastTime as Float {d:.4}\n", .{timeState, getLastTime(.seconds, f32)});
        std.debug.print("LastTime as Int {}\n", .{getLastTime(timeState, .seconds, u32)});
        std.debug.print("Runtime as Float {d:.4}\n", .{getRuntime(.seconds, f32)});
        std.debug.print("Runtime as Int {}\n", .{getStartup(timeState, .seconds, u32)});
        std.debug.print("DeltaTime as Float {d:.4}\n", .{timeState, getDeltaTime(.seconds, f32)});
        std.debug.print("DeltaTime as Int {}\n", .{timeState, getDeltaTime(.seconds, u32)});
    }
};
