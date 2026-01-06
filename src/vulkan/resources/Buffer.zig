const vk = @import("../../modules/vk.zig").c;
const ResourceSlot = @import("Resource.zig").ResourceSlot;
const ResourceState = @import("../RenderGraph.zig").ResourceState;
const rc = @import("../../configs/renderConfig.zig");
const vh = @import("../Helpers.zig");

pub const Buffer = struct {
    handle: vk.VkBuffer,
    allocation: vk.VmaAllocation,
    allocInf: vk.VmaAllocationInfo,
    gpuAddress: u64,
    count: u32 = 0,
    bindlessIndex: u32 = 0,
    state: ResourceState = .{},

    pub const BufInf = struct {
        bufId: u32,
        memUse: vh.MemUsage,
        dataSize: u64 = 0,
        length: u32,
        bufType: vh.BufferType,
    };

    pub fn create(bufId: u32, memUse: vh.MemUsage, bufType: vh.BufferType, length: u32, comptime T: type) BufInf {
        return .{
            .bufId = bufId,
            .memUse = memUse,
            .bufType = bufType,
            .length = length,
            .dataSize = @sizeOf(T),
        };
    }

    pub fn createBufferBarrier(self: *Buffer, newState: ResourceState) vk.VkBufferMemoryBarrier2 {
        const barrier =  vk.VkBufferMemoryBarrier2{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
            .srcStageMask = @intFromEnum(self.state.stage),
            .srcAccessMask = @intFromEnum(self.state.access),
            .dstStageMask = @intFromEnum(newState.stage),
            .dstAccessMask = @intFromEnum(newState.access),
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .buffer = self.handle,
            .offset = 0,
            .size = vk.VK_WHOLE_SIZE, // whole Buffer
        };
        self.state = newState;
        return barrier;
    }

    pub fn getResourceSlot(self: *const Buffer) ResourceSlot {
        return ResourceSlot{ .index = self.bindlessIndex, .count = self.count };
    }
};
