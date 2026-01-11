const Swapchain = @import("../components/Swapchain.zig").Swapchain;
const rc = @import("../../configs/renderConfig.zig");
const vk = @import("../../modules/vk.zig").c;
const vh = @import("../systems/Helpers.zig");

pub const Queue = struct {
    handle: vk.VkQueue = undefined,

    pub fn init(gpi: vk.VkDevice, family: u32, index: u32) Queue {
        var queue: vk.VkQueue = undefined;
        vk.vkGetDeviceQueue(gpi, family, index, &queue);
        return .{ .handle = queue };
    }

    pub fn submit(self: *const Queue, waitSemInfos: []const vk.VkSemaphoreSubmitInfo, cmdSubmitInf: []const vk.VkCommandBufferSubmitInfo, signalSemInfos: []const vk.VkSemaphoreSubmitInfo) !void {
        const submitInf = vk.VkSubmitInfo2{
            .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .waitSemaphoreInfoCount = @intCast(waitSemInfos.len),
            .pWaitSemaphoreInfos = waitSemInfos.ptr,
            .commandBufferInfoCount = @intCast(cmdSubmitInf.len),
            .pCommandBufferInfos = cmdSubmitInf.ptr,
            .signalSemaphoreInfoCount = @intCast(signalSemInfos.len),
            .pSignalSemaphoreInfos = signalSemInfos.ptr,
        };
        try vh.check(vk.vkQueueSubmit2(self.handle, 1, &submitInf, null), "Failed main submission");
    }

    pub fn present(self: *const Queue, handles: []vk.VkSwapchainKHR, imgIndices: []u32, waitSems: []vk.VkSemaphore) !void {
        const presentInf = vk.VkPresentInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = @intCast(waitSems.len),
            .pWaitSemaphores = waitSems.ptr,
            .swapchainCount = @intCast(handles.len),
            .pSwapchains = handles.ptr,
            .pImageIndices = imgIndices.ptr,
        };

        const result = vk.vkQueuePresentKHR(self.handle, &presentInf);
        if (result != vk.VK_SUCCESS and result != vk.VK_ERROR_OUT_OF_DATE_KHR and result != vk.VK_SUBOPTIMAL_KHR) {
            try vh.check(result, "Failed to present swapchain image");
        }
    }
};
