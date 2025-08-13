const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const CmdManager = @import("CmdManager.zig").CmdManager;
const check = @import("error.zig").check;
const createTimeline = @import("primitives.zig").createTimeline;
const getTimelineVal = @import("primitives.zig").getTimelineVal;
const waitForTimeline = @import("primitives.zig").waitForTimeline;
const createSemaphore = @import("primitives.zig").createSemaphore;
const MAX_IN_FLIGHT = @import("../config.zig").MAX_IN_FLIGHT;

pub const Scheduler = struct {
    gpi: c.VkDevice,
    frameInFlight: u8 = 0,
    maxInFlight: u8,
    cpuSyncTimeline: c.VkSemaphore,
    totalFrames: u64 = 0,
    lastChecked: u64 = 0,
    passFinishedSemaphores: [MAX_IN_FLIGHT]c.VkSemaphore,

    pub fn init(context: *const Context, maxInFlight: u8) !Scheduler {
        std.debug.print("Scheduler: In Flight {}\n", .{maxInFlight});
        var passFinishedSemaphores: [MAX_IN_FLIGHT]c.VkSemaphore = undefined;
        for (0..maxInFlight) |i| passFinishedSemaphores[i] = try createSemaphore(context.gpi);

        return Scheduler{
            .gpi = context.gpi,
            .cpuSyncTimeline = try createTimeline(context.gpi),
            .maxInFlight = maxInFlight,
            .passFinishedSemaphores = passFinishedSemaphores,
        };
    }

    pub fn deinit(self: *Scheduler) void {
        c.vkDestroySemaphore(self.gpi, self.cpuSyncTimeline, null);
        for (self.passFinishedSemaphores) |sem| c.vkDestroySemaphore(self.gpi, sem, null);
    }

    pub fn waitForGPU(self: *Scheduler) !void {
        const gpi = self.gpi;
        if (self.totalFrames < self.maxInFlight) return;
        const waitVal = self.totalFrames - self.maxInFlight + 1;

        if (self.lastChecked == waitVal) return;

        const curVal = try getTimelineVal(gpi, self.cpuSyncTimeline);
        if (curVal >= waitVal) {
            self.lastChecked = waitVal;
            return;
        }
        try waitForTimeline(gpi, self.cpuSyncTimeline, waitVal, 1_000_000_000); // Only wait if GPU is behind
    }

    pub fn waitForFrame(self: *Scheduler, gpi: c.VkDevice, frameIndex: u64) !void {
        try waitForTimeline(gpi, self.cpuSyncTimeline, frameIndex, std.math.maxInt(u64));
    }

    pub fn nextFrame(self: *Scheduler) void {
        self.frameInFlight = (self.frameInFlight + 1) % self.maxInFlight;
        self.totalFrames += 1;
    }
};
