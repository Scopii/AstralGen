const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const TextureBase = @import("../types/res/TextureBase.zig").TextureBase;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const BufferBase = @import("../types/res/BufferBase.zig").BufferBase;
const DescriptorMan = @import("DescriptorMan.zig").DescriptorMan;
const PushData = @import("../types/res/PushData.zig").PushData;
const rc = @import("../../configs/renderConfig.zig");
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const vhT = @import("../help/Types.zig");
const vhE = @import("../help/Enums.zig");
const Allocator = std.mem.Allocator;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

pub const Transfer = struct {
    srcOffset: u64,
    dstResId: BufferMeta.BufId,
    dstOffset: u64,
    size: u64,
};

pub const ResourceStorage = struct {
    stagingBuffer: BufferBase,
    stagingOffset: u64 = 0,
    transfers: std.array_list.Managed(Transfer),

    pub fn init(alloc: Allocator, vma: *const Vma) !ResourceStorage {
        return .{
            .stagingBuffer = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE),
            .transfers = std.array_list.Managed(Transfer).init(alloc),
        };
    }

    pub fn deinit(self: *ResourceStorage, vma: *const Vma) void {
        vma.freeRawBuffer(self.stagingBuffer.handle, self.stagingBuffer.allocation);
        self.transfers.deinit();
    }

    pub fn resetTransfers(self: *ResourceStorage) void {
        self.stagingOffset = 0;
        self.transfers.clearRetainingCapacity();
    }
};
