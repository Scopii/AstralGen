const LinkedMap = @import("../../structures/LinkedMap.zig").LinkedMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
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
    stagingBuffer: Buffer,
    stagingOffset: u64 = 0,
    fullUpdates: LinkedMap(Transfer, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},

    pub fn init(vma: *const Vma) !ResourceUpdater {
        return .{
            .stagingBuffer = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE),
        };
    }

    pub fn deinit(self: *ResourceUpdater, vma: *const Vma) void {
        vma.freeBufferRaw(self.stagingBuffer.handle, self.stagingBuffer.allocation);
    }

    pub fn resetUpdates(self: *ResourceUpdater) void {
        self.stagingOffset = 0;
        self.fullUpdates.clear();
    }

    pub fn stageBufferUpdate(self: *ResourceUpdater, bufId: BufferMeta.BufId, bytes: []const u8, dstSlot: u8) !void {
        const stagingOffset = self.stagingOffset;
        if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        self.fullUpdates.upsert(bufId.val, .{ .srcOffset = stagingOffset, .dstResId = bufId, .dstOffset = 0, .size = bytes.len, .dstSlot = dstSlot });
        self.stagingOffset += (bytes.len + 15) & ~@as(u64, 15);

        const stagingPtr: [*]u8 = @ptrCast(self.stagingBuffer.mappedPtr);
        @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);
    }
};
