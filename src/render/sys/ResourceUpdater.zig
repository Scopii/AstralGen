const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const Texture = @import("../types/res/Texture.zig").Texture;
const rc = @import("../../.configs/renderConfig.zig");
const vk = @import("../../.modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

pub const BufTransfer = struct { // Should be BufferTransfer
    srcOffset: u64,
    dstResId: BufferMeta.BufId,
    dstOffset: u64,
    size: u64,
};

pub const TexTransfer = struct {
    srcOffset: u64,
    dstTexId: TextureMeta.TexId,
    width: u32,
    height: u32,
};

pub const ResourceUpdater = struct {
    alloc: Allocator,
    stagingBuffers: [rc.MAX_IN_FLIGHT]Buffer,
    stagingOffsets: [rc.MAX_IN_FLIGHT]u64 = .{0} ** rc.MAX_IN_FLIGHT,

    fullUpdateLists: [rc.MAX_IN_FLIGHT]SimpleMap(BufTransfer, rc.BUF_MAX, u32, rc.BUF_MAX, 0), // Could be slot map?
    segmentUpdatesLists: [rc.MAX_IN_FLIGHT]std.ArrayList(BufTransfer),

    fullTexUpdateLists: [rc.MAX_IN_FLIGHT]SimpleMap(TexTransfer, rc.TEX_MAX, u32, rc.TEX_MAX, 0),

    pub fn init(alloc: Allocator, vma: *const Vma) !ResourceUpdater {
        var stagingBuffers: [rc.MAX_IN_FLIGHT]Buffer = undefined;
        var fullUpdateLists: [rc.MAX_IN_FLIGHT]SimpleMap(BufTransfer, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = undefined;
        var segmentUpdatesLists: [rc.MAX_IN_FLIGHT]std.ArrayList(BufTransfer) = undefined;
        var fullTexUpdateLists: [rc.MAX_IN_FLIGHT]SimpleMap(TexTransfer, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = undefined;

        for (0..rc.MAX_IN_FLIGHT) |i| {
            stagingBuffers[i] = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE);
            fullUpdateLists[i] = .{};
            segmentUpdatesLists[i] = try std.ArrayList(BufTransfer).initCapacity(alloc, 512);
            fullTexUpdateLists[i] = .{};
        }

        return .{
            .alloc = alloc,
            .stagingBuffers = stagingBuffers,
            .fullUpdateLists = fullUpdateLists,
            .segmentUpdatesLists = segmentUpdatesLists,
            .fullTexUpdateLists = fullTexUpdateLists,
        };
    }

    pub fn deinit(self: *ResourceUpdater, vma: *const Vma) void {
        for (&self.stagingBuffers) |*stagingBuffer| vma.freeBufferRaw(stagingBuffer.handle, stagingBuffer.allocation);
        for (&self.segmentUpdatesLists) |*list| list.deinit(self.alloc);
    }

    pub fn getTexUpdates(self: *ResourceUpdater, flightId: u8) []TexTransfer {
        return self.fullTexUpdateLists[flightId].getItems();
    }

    pub fn stageTextureUpdate(self: *ResourceUpdater, texId: TextureMeta.TexId, bytes: []const u8, width: u32, height: u32, flightId: u8) !void {
        const stagingOffset = self.stagingOffsets[flightId];
        if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        const texTransfer = TexTransfer{ .srcOffset = stagingOffset, .dstTexId = texId, .width = width, .height = height };
        self.fullTexUpdateLists[flightId].upsert(texId.val, texTransfer);
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

    pub fn stageBufferUpdate(self: *ResourceUpdater, bufId: BufferMeta.BufId, bytes: []const u8, flightId: u8) !void {
        const stagingOffset = self.stagingOffsets[flightId];
        if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        const transfer = BufTransfer{ .srcOffset = stagingOffset, .dstResId = bufId, .dstOffset = 0, .size = bytes.len };
        self.fullUpdateLists[flightId].upsert(bufId.val, transfer);
        self.stagingOffsets[flightId] += (bytes.len + 15) & ~@as(u64, 15);

        const stagingPtr: [*]u8 = @ptrCast(self.stagingBuffers[flightId].mappedPtr);
        @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);
    }

    pub fn stageBufferSegmentUpdate(self: *ResourceUpdater, bufId: BufferMeta.BufId, bytes: []const u8, flightId: u8, offset: u64) !void {
        const stagingOffset = self.stagingOffsets[flightId];
        if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        const transfer = BufTransfer{ .srcOffset = stagingOffset, .dstResId = bufId, .dstOffset = offset, .size = bytes.len };
        try self.segmentUpdatesLists[flightId].append(self.alloc, transfer);
        self.stagingOffsets[flightId] += (bytes.len + 15) & ~@as(u64, 15);

        const stagingPtr: [*]u8 = @ptrCast(self.stagingBuffers[flightId].mappedPtr);
        @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);
    }
};
