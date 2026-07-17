const ClearValue = @import("../pass/AttachmentUse.zig").ClearValue;
const vk = @import("../../../.modules/vk.zig").c;
const vhF = @import("../../help/Functions.zig");
const vhE = @import("../../help/Enums.zig");

pub const Texture = struct {
    typ: vhE.TexTyp,
    img: vk.VkImage,
    view: vk.VkImageView,
    allocation: vk.VmaAllocation,
    state: TextureState = .{},
    extent: vk.VkExtent3D,
    descIndex: ?u31 = null,
    sampledDescIndex: ?u31 = null,

    pub const TextureState = struct {
        stage: vhE.PipeStage = .TopOfPipe,
        access: vhE.PipeAccess = .None,
        layout: vhE.ImageLayout = .Undefined,
    };

    pub fn createAttachment(self: *const Texture, format: vhE.TexTyp, clear: ?ClearValue) !vk.VkRenderingAttachmentInfo {
        var clearValue: vk.VkClearValue = undefined;

        if (clear) |clearColor| {
            switch (clearColor) {
                .color => |color| switch (format) {
                    .Color16, .Color8, .Swapchain => clearValue = vk.VkClearValue{ .color = .{ .float32 = .{ color.R, color.G, color.B, color.A } } },
                    else => return error.ColorFormatHasDepthColor,
                },
                .depth => |depthStencil| switch (format) {
                    .Depth32, .Stencil8 => clearValue = vk.VkClearValue{ .depthStencil = .{ .depth = depthStencil.depthStencil.depth, .stencil = depthStencil.depthStencil.stencil } },
                    else => return error.DepthFormatHasDepthColor,
                },
            }
        }

        return vk.VkRenderingAttachmentInfo{
            .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = self.view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
            .loadOp = if (clear != null) vk.VK_ATTACHMENT_LOAD_OP_CLEAR else vk.VK_ATTACHMENT_LOAD_OP_LOAD,
            .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
            .clearValue = clearValue,
        };
    }

    pub fn createImageBarrier(self: *Texture, newState: TextureState) vk.VkImageMemoryBarrier2 {
        const subRange = vhF.createSubresourceRange(self.typ.getImageAspectFlags(), 0, 1, 0, 1);

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
            .subresourceRange = subRange,
        };
        self.state = newState;
        return barrier;
    }

    pub fn createMemoryBarrier(self: *Texture, newState: TextureState) vk.VkMemoryBarrier2 {
        const barrier = vk.VkMemoryBarrier2{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = @intFromEnum(self.state.stage),
            .srcAccessMask = @intFromEnum(self.state.access),
            .dstStageMask = @intFromEnum(newState.stage),
            .dstAccessMask = @intFromEnum(newState.access),
        };
        self.state = newState;
        return barrier;
    }
};
