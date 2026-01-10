const vk = @import("../../modules/vk.zig").c;
const vh = @import("../systems/Helpers.zig");

pub const Queue = struct {
    handle: vk.VkQueue = undefined,

    pub fn init(gpi: vk.VkDevice, family: u32, index: u32) Queue {
        var queue: vk.VkQueue = undefined;
        vk.vkGetDeviceQueue(gpi, family, index, &queue);
        return .{ .handle = queue };
    }

    pub fn submit(self: *Queue, waitSemInfos: []vk.VkSemaphoreSubmitInfo, cmdSubmitInf: vk.VkCommandBufferSubmitInfo, signalSemInfos: []vk.VkSemaphoreSubmitInfo) !void {
        const submitInf = vk.VkSubmitInfo2{
            .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .waitSemaphoreInfoCount = @intCast(waitSemInfos.len),
            .pWaitSemaphoreInfos = waitSemInfos.ptr,
            .commandBufferInfoCount = 1,
            .pCommandBufferInfos = &cmdSubmitInf,
            .signalSemaphoreInfoCount = @intCast(signalSemInfos.len),
            .pSignalSemaphoreInfos = signalSemInfos.ptr,
        };
        try vh.check(vk.vkQueueSubmit2(self.handle, 1, &submitInf, null), "Failed main submission");
    }
};
