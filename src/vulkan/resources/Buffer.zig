const vk = @import("../../modules/vk.zig").c;
const ResourceSlot = @import("Resource.zig").ResourceSlot;
const ResourceState = @import("../RenderGraph.zig").ResourceState;
const rc = @import("../../configs/renderConfig.zig");
const ve = @import("../Helpers.zig");

pub const Buffer = struct {
    handle: vk.VkBuffer,
    allocation: vk.VmaAllocation,
    allocInf: vk.VmaAllocationInfo,
    gpuAddress: u64,
    count: u32 = 0,
    bindlessIndex: u32 = 0,
    state: ResourceState = .{},

    pub fn getResourceSlot(self: *Buffer) ResourceSlot {
        return ResourceSlot{ .index = self.bindlessIndex, .count = self.count };
    }

    pub const BufInf = struct {
        bufId: u32,
        memUse: ve.MemUsage,
        dataSize: u64 = 0,
        length: u32,
        bufType: ve.BufferType,
    };

    pub fn create(bufId: u32, memUse: ve.MemUsage, bufType: ve.BufferType, length: u32, comptime T: type) BufInf {
        return .{
            .bufId = bufId,
            .memUse = memUse,
            .bufType = bufType,
            .length = length,
            .dataSize = @sizeOf(T),
        };
    }
};
