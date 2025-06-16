const std = @import("std");
const c = @import("../../c.zig");
const check = @import("../error.zig").check;
//const Allocator = std.mem.Allocator;
const VkAllocator = @import("../vma.zig").VkAllocator;
const RenderImage = @import("RenderImage.zig").RenderImage;
const Context = @import("Context.zig").Context;
const createAllocatedImageInfo = @import("RenderImage.zig").createAllocatedImageInfo;
const createAllocatedImageViewInfo = @import("RenderImage.zig").createAllocatedImageViewInfo;

pub const ResourceManager = struct {
    vkAlloc: VkAllocator,
    gpi: c.VkDevice,

    pub fn init(context: *const Context) !ResourceManager {
        return .{
            .vkAlloc = try VkAllocator.init(context.instance, context.gpi, context.gpu),
            .gpi = context.gpi,
        };
    }

    pub fn createRenderImage(self: *const ResourceManager, extent: c.VkExtent2D) !RenderImage {
        const drawImageExtent = c.VkExtent3D{
            .width = extent.width,
            .height = extent.height,
            .depth = 1,
        };

        const drawImageUsages = c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            c.VK_IMAGE_USAGE_STORAGE_BIT |
            c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        var renderImage: RenderImage = undefined;
        renderImage.format = c.VK_FORMAT_R16G16B16A16_SFLOAT;
        renderImage.extent3d = drawImageExtent;

        // Allocation from GPU local memory
        const renderImageInfo = createAllocatedImageInfo(renderImage.format, drawImageUsages, renderImage.extent3d);
        const renderImageAllocInfo = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
            .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        };

        // Allocation and creation
        try check(c.vmaCreateImage(
            self.vkAlloc.handle,
            &renderImageInfo,
            &renderImageAllocInfo,
            &renderImage.image,
            &renderImage.allocation,
            null,
        ), "Could not create Render Image");
        // Build Image View for the draw Image to use for rendering
        const renderViewInfo = createAllocatedImageViewInfo(renderImage.format, renderImage.image, c.VK_IMAGE_ASPECT_COLOR_BIT);
        try check(c.vkCreateImageView(self.gpi, &renderViewInfo, null, &renderImage.view), "Could not create Render Image View");
        return renderImage;
    }

    pub fn destroyRenderImage(self: *const ResourceManager, image: RenderImage) void {
        c.vkDestroyImageView(self.gpi, image.view, null);
        c.vmaDestroyImage(self.vkAlloc.handle, image.image, image.allocation);
    }

    pub fn deinit(self: *ResourceManager) void {
        self.vkAlloc.deinit();
    }
};
