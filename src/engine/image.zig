const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;

pub const ImageBucket = struct {
    images: []c.VkImage,
    imageViews: []c.VkImageView,

    pub fn init(alloc: Allocator, imageCount: u32, gpi: c.VkDevice, swapchain: c.VkSwapchainKHR, format: c.VkFormat) !ImageBucket {
        var count = imageCount;
        const images: []c.VkImage = try createImages(alloc, gpi, swapchain, &count);
        const imageViews: []c.VkImageView = try createImageViews(alloc, gpi, images, format);

        return .{
            .images = images,
            .imageViews = imageViews,
        };
    }

    pub fn deinit(self: *ImageBucket, alloc: Allocator, gpi: c.VkDevice) void {
        for (self.imageViews) |view| {
            c.vkDestroyImageView(gpi, view, null);
        }
        alloc.free(self.images);
        alloc.free(self.imageViews);
    }
};

fn createImages(alloc: Allocator, gpi: c.VkDevice, swapchain: c.VkSwapchainKHR, imageCount: *u32) ![]c.VkImage {
    // First get the actual count if not provided
    if (imageCount.* == 0) try check(c.vkGetSwapchainImagesKHR(gpi, swapchain, imageCount, null), "Could not get Swapchain Images");

    const images = try alloc.alloc(c.VkImage, imageCount.*);
    const result = c.vkGetSwapchainImagesKHR(gpi, swapchain, imageCount, images.ptr);

    if (result != c.VK_SUCCESS) {
        alloc.free(images);
        return error.FailedToCreateSwapchainImages; // Use proper error instead of panic
    }
    return images;
}

fn createImageViews(alloc: Allocator, gpi: c.VkDevice, images: []c.VkImage, format: c.VkFormat) ![]c.VkImageView {
    const imageViews = try alloc.alloc(c.VkImageView, images.len);
    errdefer alloc.free(imageViews);

    for (images, 0..) |image, i| {
        const imageViewInfo = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = format,
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        const success = c.vkCreateImageView(gpi, &imageViewInfo, null, &imageViews[i]);
        if (success != c.VK_SUCCESS) {
            // Clean up any image views created so far
            for (0..i) |j| {
                c.vkDestroyImageView(gpi, imageViews[j], null);
            }
            return error.ImageViewCreationFailed;
        }
    }
    return imageViews;
}
