const rc = @import("../../../configs/renderConfig.zig");
const PushData = @import("PushData.zig").PushData;
const vk = @import("../../../modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const BufferBase = struct {
    handle: vk.VkBuffer,
    allocation: vk.VmaAllocation,
    mappedPtr: ?*anyopaque,
    gpuAddress: u64,
    size: vk.VkDeviceSize,
    curCount: u32 = 0,
    state: BufferState = .{},

    descIndex: u32 = 0,

    pub const BufferState = struct {
        stage: vhE.PipeStage = .TopOfPipe,
        access: vhE.PipeAccess = .None,
    };

    pub fn createBufferBarrier(self: *BufferBase, newState: BufferState) vk.VkBufferMemoryBarrier2 {
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
};
