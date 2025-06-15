const std = @import("std");
const c = @import("../../c.zig");
const check = @import("../error.zig").check;
const VkAllocator = @import("../vma.zig").VkAllocator;

pub const RenderImage = struct {
    allocation: c.VmaAllocation,
    image: c.VkImage,
    view: c.VkImageView,
    extent3d: c.VkExtent3D,
    format: c.VkFormat,
};

pub fn createAllocatedImageInfo(format: c.VkFormat, usageFlags: c.VkImageUsageFlags, extent3d: c.VkExtent3D) c.VkImageCreateInfo {
    return c.VkImageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent3d,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT, // MSAA not used by default!
        .tiling = c.VK_IMAGE_TILING_OPTIMAL, // Optimal GPU Format, has to be changed to LINEAR for CPU Read
        .usage = usageFlags,
    };
}

pub fn createAllocatedImageViewInfo(format: c.VkFormat, image: c.VkImage, aspectFlags: c.VkImageAspectFlags) c.VkImageViewCreateInfo {
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
