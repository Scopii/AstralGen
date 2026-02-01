const PushConstants = @import("PushConstants.zig").PushConstants;
const rc = @import("../../../configs/renderConfig.zig");
const vk = @import("../../../modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const Buffer = struct {
    handle: vk.VkBuffer,
    allocation: vk.VmaAllocation,
    mappedPtr: ?*anyopaque,
    gpuAddress: u64,
    size: vk.VkDeviceSize,
    count: u32 = 0,
    bindlessIndices: [rc.MAX_IN_FLIGHT]u32 = .{0} ** rc.MAX_IN_FLIGHT,
    lastUpdatedFlightId: u8 = 0,
    state: BufferState = .{},
    typ: vhE.BufferType = .Storage,
    update: vhE.UpdateType = .Overwrite,

    pub const BufId = packed struct { val: u32 };
    pub const BufferState = struct { stage: vhE.PipeStage = .TopOfPipe, access: vhE.PipeAccess = .None };
    pub const BufInf = struct { id: BufId, mem: vhE.MemUsage, elementSize: u32, len: u32, typ: vhE.BufferType, update: vhE.UpdateType };

    pub fn create(bufInf: BufInf) BufInf {
        return bufInf;
    }

    pub fn getResourceSlot(self: *const Buffer) PushConstants.ResourceSlot {
        return .{ .index = self.bindlessIndices, .count = self.count };
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
};
