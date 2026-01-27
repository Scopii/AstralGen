const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const Queue = @import("../types/base/Queue.zig").Queue;
const rc = @import("../../configs/renderConfig.zig");
const Cmd = @import("../types/base/Cmd.zig").Cmd;
const Context = @import("Context.zig").Context;
const vhF = @import("../help/Functions.zig");
const vk = @import("../../modules/vk.zig").c;
const vkE = @import("../help/Enums.zig");
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

    pub fn beginFrame(self: *Scheduler) !u8 {
        if (rc.CPU_PROFILING == true) {
            const depth = try self.getBackpressure();
            if (depth == rc.MAX_IN_FLIGHT) std.debug.print("Frame In Flight: {}/{} BLOCKING, FlightId {}\n", .{ depth, rc.MAX_IN_FLIGHT, self.flightId }) else {
                std.debug.print("Frame In Flight: {}/{}, FlightId {}\n", .{ depth, rc.MAX_IN_FLIGHT, self.flightId });
            }
        }
        return self.flightId;
    }

    pub fn endFrame(self: *Scheduler) void {
        self.flightId = (self.flightId + 1) % self.maxInFlight;
        self.totalFrames += 1;
    }

    pub fn queueSubmit(self: *Scheduler, cmd: *const Cmd, targets: []const *Swapchain, queue: Queue) !void {
        var waitInfos: [rc.MAX_WINDOWS]vk.VkSemaphoreSubmitInfo = undefined;
        var signalInfos: [rc.MAX_WINDOWS + 1]vk.VkSemaphoreSubmitInfo = undefined;
        signalInfos[targets.len] = createSemaphoreSubmitInfo(self.cpuSyncTimeline, .AllCmds, self.totalFrames + 1);

        for (targets, 0..) |swapchain, i| {
            waitInfos[i] = createSemaphoreSubmitInfo(swapchain.acquireSems[self.flightId], .Transfer, 0);
            signalInfos[i] = createSemaphoreSubmitInfo(swapchain.renderSems[swapchain.curIndex], .AllCmds, 0);
        }
        const cmdSlice = &[_]vk.VkCommandBufferSubmitInfo{cmd.createSubmitInfo()};
        try queue.submit(waitInfos[0..targets.len], cmdSlice, signalInfos[0 .. targets.len + 1]);
    }

    pub fn queuePresent(_: *Scheduler, targets: []const *const Swapchain, queue: Queue) !void {
        var handles: [rc.MAX_WINDOWS]vk.VkSwapchainKHR = undefined;
        var imgIndices: [rc.MAX_WINDOWS]u32 = undefined;
        var waitSems: [rc.MAX_WINDOWS]vk.VkSemaphore = undefined;

        for (targets, 0..) |swapchain, i| {
            handles[i] = swapchain.handle;
            imgIndices[i] = swapchain.curIndex;
            waitSems[i] = swapchain.renderSems[swapchain.curIndex];
        }
        try queue.present(handles[0..targets.len], imgIndices[0..targets.len], waitSems[0..targets.len]);
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

        const before = if (rc.CPU_PROFILING == true) std.time.microTimestamp() else 0;
        try vhF.waitForTimeline(gpi, self.cpuSyncTimeline, waitVal, 1_000_000_000); // Only wait if GPU is behind
        const after = if (rc.CPU_PROFILING == true) std.time.microTimestamp() else 0;
        if (rc.CPU_PROFILING == true) std.debug.print("Cpu Waiting {d:.3} ms for Frame {}\n", .{ @as(f64, @floatFromInt(after - before)) * 0.001, waitVal });
    }

    pub fn getBackpressure(self: *Scheduler) !u64 {
        const gpuCompletedCount = try vhF.getTimelineVal(self.gpi, self.cpuSyncTimeline);
        if (self.totalFrames < gpuCompletedCount) return 0; // Should not happen
        return self.totalFrames - gpuCompletedCount;
    }

    pub fn waitForFrame(self: *Scheduler, gpi: vk.VkDevice, frameIndex: u64) !void {
        try vhF.waitForTimeline(gpi, self.cpuSyncTimeline, frameIndex, std.math.maxInt(u64));
    }
};

fn createSemaphoreSubmitInfo(semaphore: vk.VkSemaphore, pipeStage: vkE.PipeStage, value: u64) vk.VkSemaphoreSubmitInfo {
    return .{ .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = semaphore, .stageMask = @intFromEnum(pipeStage), .value = value };
}
