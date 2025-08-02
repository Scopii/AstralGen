const std = @import("std");
const c = @import("../c.zig");
const VkAllocator = @import("vma.zig").VkAllocator;
const Context = @import("Context.zig").Context;
const check = @import("error.zig").check;

pub const RenderImage = struct {
    allocation: c.VmaAllocation,
    image: c.VkImage,
    view: c.VkImageView,
    extent3d: c.VkExtent3D,
    format: c.VkFormat,
    curLayout: u32 = c.VK_IMAGE_LAYOUT_UNDEFINED,
};

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
        const drawImageExtent = c.VkExtent3D{ .width = extent.width, .height = extent.height, .depth = 1 };

        const drawImageUsages = c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            c.VK_IMAGE_USAGE_STORAGE_BIT |
            c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        const format = c.VK_FORMAT_R16G16B16A16_SFLOAT;

        // Allocation from GPU local memory
        const renderImageInf = createAllocatedImageInf(format, drawImageUsages, drawImageExtent);
        const renderImageAllocInf = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
            .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        };

        var image: c.VkImage = undefined;
        var allocation: c.VmaAllocation = undefined;
        var view: c.VkImageView = undefined;

        try check(c.vmaCreateImage(self.vkAlloc.handle, &renderImageInf, &renderImageAllocInf, &image, &allocation, null), "Could not create Render Image");
        const renderViewInf = createAllocatedImageViewInf(format, image, c.VK_IMAGE_ASPECT_COLOR_BIT);
        try check(c.vkCreateImageView(self.gpi, &renderViewInf, null, &view), "Could not create Render Image View");

        return .{
            .allocation = allocation,
            .image = image,
            .view = view,
            .extent3d = drawImageExtent,
            .format = format,
        };
    }

    pub fn destroyRenderImage(self: *const ResourceManager, image: RenderImage) void {
        c.vkDestroyImageView(self.gpi, image.view, null);
        c.vmaDestroyImage(self.vkAlloc.handle, image.image, image.allocation);
    }

    pub fn deinit(self: *ResourceManager) void {
        self.vkAlloc.deinit();
    }
};

pub fn createAllocatedImageInf(format: c.VkFormat, usageFlags: c.VkImageUsageFlags, extent3d: c.VkExtent3D) c.VkImageCreateInfo {
    return c.VkImageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent3d,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT, // MSAA not used by default!
        .tiling = c.VK_IMAGE_TILING_OPTIMAL, // Optimal GPU Format has to be changed to LINEAR for CPU Read
        .usage = usageFlags,
    };
}

pub fn createAllocatedImageViewInf(format: c.VkFormat, image: c.VkImage, aspectFlags: c.VkImageAspectFlags) c.VkImageViewCreateInfo {
    return c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .image = image,
        .format = format,
        .subresourceRange = c.VkImageSubresourceRange{
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .aspectMask = aspectFlags,
        },
    };
}
