const rc = @import("../../../.configs/renderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const Buffer = struct {
    descIndex: ?u31 = null,
    curCount: u32 = 0,
    handle: vk.VkBuffer,
    allocation: vk.VmaAllocation,
    gpuAddress: u64,
    size: vk.VkDeviceSize,
    mappedPtr: ?*anyopaque,

    pub const BufferState = struct {
        stage: vhE.PipeStage = .TopOfPipe,
        access: vhE.PipeAccess = .None,
    };

    pub fn makeBarrier(self: *const Buffer, oldState: BufferState, newState: BufferState) vk.VkBufferMemoryBarrier2 {
        const barrier = vk.VkBufferMemoryBarrier2{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
            .srcStageMask = @intFromEnum(oldState.stage),
            .srcAccessMask = @intFromEnum(oldState.access),
            .dstStageMask = @intFromEnum(newState.stage),
            .dstAccessMask = @intFromEnum(newState.access),
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .buffer = self.handle,
            .offset = 0,
            .size = vk.VK_WHOLE_SIZE, // whole Buffer
        };
        return barrier;
    }

    pub fn makeMemBarrier(_: *const Buffer, oldState: BufferState, newState: BufferState) vk.VkMemoryBarrier2 {
        const barrier = vk.VkMemoryBarrier2{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = @intFromEnum(oldState.stage),
            .srcAccessMask = @intFromEnum(oldState.access),
            .dstStageMask = @intFromEnum(newState.stage),
            .dstAccessMask = @intFromEnum(newState.access),
        };
        return barrier;
    }
};
