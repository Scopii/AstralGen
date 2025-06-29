const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const CmdManager = @import("../render/CmdManager.zig").CmdManager;
const Context = @import("../render/Context.zig").Context;
const check = @import("../error.zig").check;
const createTimeline = @import("../sync/primitives.zig").createTimeline;
const getTimelineVal = @import("../sync/primitives.zig").getTimelineVal;
const waitForTimeline = @import("../sync/primitives.zig").waitForTimeline;
const createSemaphore = @import("../sync/primitives.zig").createSemaphore;

pub const Scheduler = struct {
    curFrame: u8 = 0,
    maxInFlight: u8,
    acqSems: []c.VkSemaphore,
    cpuSyncTimeline: c.VkSemaphore,
    frameCount: u64 = 0,
    lastChecked: u64 = 0,

    pub fn init(context: *const Context, maxInFlight: u8) !Scheduler {
        std.debug.print("Scheduler: In Flight {}\n", .{maxInFlight});

        return Scheduler{
            .gpi = context.gpi,
            .cpuSyncTimeline = try createTimeline(context.gpi),
            .maxInFlight = maxInFlight,
        };
    }

    pub fn deinit(self: *Scheduler) void {
        c.vkDestroySemaphore(self.gpi, self.cpuSyncTimeline, null);
    }

    // New: Efficient CPU-GPU throttling
    pub fn waitForGPU(self: *Scheduler) !void {
        const gpi = self.gpi;
        if (self.frameCount < self.maxInFlight) return; // Early frames don't need waiting

        const waitVal = self.frameCount - self.maxInFlight + 1;

        // Skip check if we just waited recently (cache last check)
        if (self.lastChecked == waitVal) return;

        // Quick check - avoid syscall if already complete
        const curVal = try getTimelineVal(gpi, self.cpuSyncTimeline);
        if (curVal >= waitVal) {
            self.lastChecked = waitVal;
            return;
        }

        // Only wait if GPU is actually behind
        try waitForTimeline(gpi, self.cpuSyncTimeline, waitVal, 1_000_000_000);
    }

    pub fn waitForFrame(self: *Scheduler, gpi: c.VkDevice, frameIndex: u64) !void {
        try waitForTimeline(gpi, self.cpuSyncTimeline, frameIndex, std.math.maxInt(u64));
    }

    pub fn nextFrame(self: *Scheduler) void {
        self.curFrame = (self.curFrame + 1) % self.maxInFlight;
    }
};
