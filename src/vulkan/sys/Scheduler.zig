const vhF = @import("../help/Functions.zig");
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const std = @import("std");

pub const Scheduler = struct {
    gpi: vk.VkDevice,
    flightId: u8 = 0,
    maxInFlight: u8,
    cpuSyncTimeline: vk.VkSemaphore,
    totalFrames: u64 = 0,
    lastChecked: u64 = 0,

    pub fn init(context: *const Context, maxInFlight: u8) !Scheduler {
        std.debug.print("Scheduler: In Flight {}\n", .{maxInFlight});
        return Scheduler{
            .gpi = context.gpi,
            .cpuSyncTimeline = try vhF.createTimeline(context.gpi),
            .maxInFlight = maxInFlight,
        };
    }

    pub fn deinit(self: *Scheduler) void {
        vk.vkDestroySemaphore(self.gpi, self.cpuSyncTimeline, null);
    }

    pub fn waitForGPU(self: *Scheduler) !void {
        const gpi = self.gpi;
        if (self.totalFrames < self.maxInFlight) return;
        const waitVal = self.totalFrames - self.maxInFlight + 1;

        if (self.lastChecked == waitVal) return;

        const curVal = try vhF.getTimelineVal(gpi, self.cpuSyncTimeline);
        if (curVal >= waitVal) {
            self.lastChecked = waitVal;
            return;
        }
        try vhF.waitForTimeline(gpi, self.cpuSyncTimeline, waitVal, 1_000_000_000); // Only wait if GPU is behind
    }

    pub fn waitForFrame(self: *Scheduler, gpi: vk.VkDevice, frameIndex: u64) !void {
        try vhF.waitForTimeline(gpi, self.cpuSyncTimeline, frameIndex, std.math.maxInt(u64));
    }

    pub fn nextFrame(self: *Scheduler) void {
        self.flightId = (self.flightId + 1) % self.maxInFlight;
        self.totalFrames += 1;
    }
};