const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../.configs/renderConfig.zig");
const vk = @import("../../.modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

pub const Transfer = struct {
    srcOffset: u64,
    dstResId: BufferMeta.BufId,
    dstOffset: u64,
    size: u64,
    dstSlot: u8,
};

pub const ResourceUpdater = struct {
    stagingBuffers: [rc.MAX_IN_FLIGHT]Buffer,
    stagingOffsets: [rc.MAX_IN_FLIGHT]u64 = .{0} ** rc.MAX_IN_FLIGHT,
    fullUpdateLists: [rc.MAX_IN_FLIGHT]LinkedMap(Transfer, rc.BUF_MAX, u32, rc.BUF_MAX, 0),

    pub fn init(vma: *const Vma) !ResourceUpdater {
        var stagingBuffers: [rc.MAX_IN_FLIGHT]Buffer = undefined;
        var fullUpdateLists: [rc.MAX_IN_FLIGHT]LinkedMap(Transfer, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = undefined;
        
        for (0..rc.MAX_IN_FLIGHT) |i| {
            stagingBuffers[i] = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE);
            fullUpdateLists[i] = .{};
        }

        return .{
            .stagingBuffers = stagingBuffers,
            .fullUpdateLists = fullUpdateLists,
        };
    }

    pub fn deinit(self: *ResourceUpdater, vma: *const Vma) void {
        for (&self.stagingBuffers) |*stagingBuffer| vma.freeBufferRaw(stagingBuffer.handle, stagingBuffer.allocation);
    }

    pub fn resetUpdates(self: *ResourceUpdater, flightId: u8) void {
        self.stagingOffsets[flightId] = 0;
        self.fullUpdateLists[flightId].clear();
    }

    pub fn getUpdates(self: *ResourceUpdater, flightId: u8) []Transfer {
        return self.fullUpdateLists[flightId].getItems();
    }

    pub fn getStagingBuffer(self: *ResourceUpdater, flightId: u8) vk.VkBuffer {
        return self.stagingBuffers[flightId].handle;
    }

    pub fn stageBufferUpdate(self: *ResourceUpdater, bufId: BufferMeta.BufId, bytes: []const u8, dstSlot: u8, flightId: u8) !void {
        const stagingOffset = self.stagingOffsets[flightId];
        const fullUpdates = &self.fullUpdateLists[flightId];
        if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        fullUpdates.upsert(bufId.val, .{ .srcOffset = stagingOffset, .dstResId = bufId, .dstOffset = 0, .size = bytes.len, .dstSlot = dstSlot });
        self.stagingOffsets[flightId] += (bytes.len + 15) & ~@as(u64, 15);

        const stagingPtr: [*]u8 = @ptrCast(self.stagingBuffers[flightId].mappedPtr);
        @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);
    }
};
