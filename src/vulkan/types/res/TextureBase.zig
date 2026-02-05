const vk = @import("../../../modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const TextureBase = struct {
    img: vk.VkImage,
    view: vk.VkImageView,
    viewInf: vk.VkImageViewCreateInfo,
    texType: vhE.TextureType,
    extent: vk.VkExtent3D,
    state: TextureState = .{},

    pub const TextureState = struct { stage: vhE.PipeStage = .TopOfPipe, access: vhE.PipeAccess = .None, layout: vhE.ImageLayout = .Undefined };

    pub fn getAspectMask(self: *const TextureBase) vk.VkImageAspectFlags {
        return self.viewInf.subresourceRange.aspectMask;
    }

    pub fn getViewCreateInfo(self: *const TextureBase) vk.VkImageViewCreateInfo {
        return self.viewInf;
    }

    pub fn createAttachment(self: *const TextureBase, clear: bool) vk.VkRenderingAttachmentInfo {
        const clearValue: vk.VkClearValue = switch (self.texType) {
            .Color => .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.1, 1.0 } } },
            .Depth, .Stencil => .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
        };

        return vk.VkRenderingAttachmentInfo{
            .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = self.view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
            .loadOp = if (clear) vk.VK_ATTACHMENT_LOAD_OP_CLEAR else vk.VK_ATTACHMENT_LOAD_OP_LOAD,
            .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
            .clearValue = clearValue,
        };
    }

    pub fn createImageBarrier(self: *TextureBase, newState: TextureState) vk.VkImageMemoryBarrier2 {
        const aspectMask: vk.VkImageAspectFlagBits = switch (self.texType) {
            .Color => vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .Depth => vk.VK_IMAGE_ASPECT_DEPTH_BIT,
            .Stencil => vk.VK_IMAGE_ASPECT_STENCIL_BIT,
        };

        const barrier = vk.VkImageMemoryBarrier2{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = @intFromEnum(self.state.stage),
            .srcAccessMask = @intFromEnum(self.state.access),
            .dstStageMask = @intFromEnum(newState.stage),
            .dstAccessMask = @intFromEnum(newState.access),
            .oldLayout = @intFromEnum(self.state.layout),
            .newLayout = @intFromEnum(newState.layout),
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .image = self.img,
            .subresourceRange = createSubresourceRange(aspectMask, 0, 1, 0, 1),
        };
        self.state = newState;
        return barrier;
    }
};

fn createSubresourceRange(mask: u32, mipLevel: u32, levelCount: u32, arrayLayer: u32, layerCount: u32) vk.VkImageSubresourceRange {
    return vk.VkImageSubresourceRange{ .aspectMask = mask, .baseMipLevel = mipLevel, .levelCount = levelCount, .baseArrayLayer = arrayLayer, .layerCount = layerCount };
}
