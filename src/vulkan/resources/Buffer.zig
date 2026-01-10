const vk = @import("../../modules/vk.zig").c;
const ResourceSlot = @import("PushConstants.zig").ResourceSlot;
const rc = @import("../../configs/renderConfig.zig");
const vh = @import("../Helpers.zig");

pub const Buffer = struct {
    handle: vk.VkBuffer,
    allocation: vk.VmaAllocation,
    mappedPtr: ?*anyopaque,
    gpuAddress: u64,
    size: vk.VkDeviceSize,
    count: u32 = 0,
    bindlessIndex: u32 = 0,
    state: BufferState = .{},

    pub const BufferState = struct {
        stage: vh.PipeStage = .TopOfPipe,
        access: vh.PipeAccess = .None,
    };

    pub const BufId = packed struct { val: u32 };

    pub const BufInf = struct {
        id: BufId,
        mem: vh.MemUsage,
        elementSize: u32,
        len: u32,
        typ: vh.BufferType,
    };

    pub fn create(bufInf: BufInf) BufInf {
        return bufInf;
    }

    pub fn createBufferBarrier(self: *Buffer, newState: BufferState) vk.VkBufferMemoryBarrier2 {
        const barrier = vk.VkBufferMemoryBarrier2{
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
