const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const SimpleBuffer = @import("../types/res/Buffer.zig").SimpleBuffer;
const Texture = @import("../types/res/Texture.zig").Texture;
const TexId = @import("../../.configs/idConfig.zig").TexId;
const BufId = @import("../../.configs/idConfig.zig").BufId;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../.configs/renderConfig.zig");
const vk = @import("../../.modules/vk.zig").c;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const BufTransfer = struct { // Should be BufferTransfer
    srcOffset: u64,
    dstResId: BufId,
    dstOffset: u64,
    size: u64,
};

pub const TexTransfer = struct {
    srcOffset: u64,
    dstTexId: TexId,
    width: u32,
    height: u32,
};

pub const ResourceUpdater = struct {
    alloc: Allocator,
    stagingBuffers: [rc.MAX_IN_FLIGHT]SimpleBuffer,
    stagingOffsets: [rc.MAX_IN_FLIGHT]u64 = @splat(0),

    fullUpdateLists: [rc.MAX_IN_FLIGHT]SimpleIdMap(BufTransfer, rc.BUF_MAX, BufId, rc.BUF_MAX * rc.MAX_IN_FLIGHT, 0) = @splat(.{}), // Could be slot map?
    segmentUpdatesLists: [rc.MAX_IN_FLIGHT]std.ArrayList(BufTransfer),

    fullTexUpdateLists: [rc.MAX_IN_FLIGHT]SimpleIdMap(TexTransfer, rc.TEX_MAX, TexId, rc.TEX_MAX * rc.MAX_IN_FLIGHT, 0) = @splat(.{}),

    pub fn init(alloc: Allocator, vma: *const Vma) !ResourceUpdater {
        var stagingBuffers: [rc.MAX_IN_FLIGHT]SimpleBuffer = undefined;
        var segmentUpdatesLists: [rc.MAX_IN_FLIGHT]std.ArrayList(BufTransfer) = undefined;

        for (0..rc.MAX_IN_FLIGHT) |i| {
            stagingBuffers[i] = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE);
            segmentUpdatesLists[i] = try std.ArrayList(BufTransfer).initCapacity(alloc, 512);
        }

        return .{
            .alloc = alloc,
            .stagingBuffers = stagingBuffers,
            .segmentUpdatesLists = segmentUpdatesLists,
        };
    }

    pub fn deinit(self: *ResourceUpdater, vma: *const Vma) void {
        for (&self.stagingBuffers) |*stagingBuffer| vma.freeBufferRaw(stagingBuffer.handle, stagingBuffer.allocation);
        for (&self.segmentUpdatesLists) |*list| list.deinit(self.alloc);
    }

    pub fn getTexUpdates(self: *ResourceUpdater, flightId: u8) []TexTransfer {
        return self.fullTexUpdateLists[flightId].getItems();
    }

    pub fn stageTextureUpdate(self: *ResourceUpdater, texId: TexId, bytes: []const u8, width: u32, height: u32, flightId: u8) !void {
        const stagingOffset = self.stagingOffsets[flightId];
        if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        const texTransfer = TexTransfer{ .srcOffset = stagingOffset, .dstTexId = texId, .width = width, .height = height };
        self.fullTexUpdateLists[flightId].upsert(texId, texTransfer);
        self.stagingOffsets[flightId] += (bytes.len + 15) & ~@as(u64, 15);

        const stagingPtr: [*]u8 = @ptrCast(self.stagingBuffers[flightId].mappedPtr);
        @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);
    }

    pub fn resetUpdates(self: *ResourceUpdater, flightId: u8) void {
        self.stagingOffsets[flightId] = 0;
        self.fullUpdateLists[flightId].clear();
        self.fullTexUpdateLists[flightId].clear();
        self.segmentUpdatesLists[flightId].clearRetainingCapacity();
    }

    pub fn getFullUpdates(self: *ResourceUpdater, flightId: u8) []BufTransfer {
        return self.fullUpdateLists[flightId].getItems();
    }

    pub fn getSegmentUpdates(self: *ResourceUpdater, flightId: u8) []BufTransfer {
        return self.segmentUpdatesLists[flightId].items;
    }

    pub fn getStagingBuffer(self: *ResourceUpdater, flightId: u8) vk.VkBuffer {
        return self.stagingBuffers[flightId].handle;
    }

    pub fn stageBufferUpdate(self: *ResourceUpdater, bufId: BufId, bytes: []const u8, flightId: u8) !void {
        const stagingOffset = self.stagingOffsets[flightId];
        if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        const transfer = BufTransfer{ .srcOffset = stagingOffset, .dstResId = bufId, .dstOffset = 0, .size = bytes.len };
        self.fullUpdateLists[flightId].upsert(bufId, transfer);
        self.stagingOffsets[flightId] += (bytes.len + 15) & ~@as(u64, 15);

        const stagingPtr: [*]u8 = @ptrCast(self.stagingBuffers[flightId].mappedPtr);
        @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);
    }

    pub fn stageBufferSegmentUpdate(self: *ResourceUpdater, bufId: BufId, bytes: []const u8, flightId: u8, offset: u64) !void {
        const stagingOffset = self.stagingOffsets[flightId];
        if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        const transfer = BufTransfer{ .srcOffset = stagingOffset, .dstResId = bufId, .dstOffset = offset, .size = bytes.len };
        try self.segmentUpdatesLists[flightId].append(self.alloc, transfer);
        self.stagingOffsets[flightId] += (bytes.len + 15) & ~@as(u64, 15);

        const stagingPtr: [*]u8 = @ptrCast(self.stagingBuffers[flightId].mappedPtr);
        @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);
    }
};
