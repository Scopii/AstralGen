const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("../error.zig").check;
const createSemaphore = @import("../sync/primitives.zig").createSemaphore;

pub const SwapBucket = struct {
    image: c.VkImage,
    view: c.VkImageView,

    pub fn deinit(self: *SwapBucket, gpi: c.VkDevice) void {
        c.vkDestroyImageView(gpi, self.view, null);
    }
};

pub fn createSwapBuckets(alloc: Allocator, imgCount: u32, gpi: c.VkDevice, swapchain: c.VkSwapchainKHR, format: c.VkFormat) ![]SwapBucket {
    var count = imgCount;

    if (count == 0) try check(c.vkGetSwapchainImagesKHR(gpi, swapchain, &count, null), "Could not get Swapchain Images");
    const images = try alloc.alloc(c.VkImage, count);
    defer alloc.free(images);

    try check(c.vkGetSwapchainImagesKHR(gpi, swapchain, &count, images.ptr), "Failed to get swapchain images");
    const buckets = try alloc.alloc(SwapBucket, count);
    errdefer alloc.free(buckets); // Free if anything fails below

    var initCount: u32 = 0;
    errdefer {
        // Clean up any partially created resources
        for (0..initCount) |i| {
            if (buckets[i].view != null) c.vkDestroyImageView(gpi, buckets[i].view, null);
        }
    }

    for (0..count) |i| {
        // Create image view
        const imgViewInf = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = images[i],
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
        try check(c.vkCreateImageView(gpi, &imgViewInf, null, &buckets[i].view), "Failed to create image view");

        buckets[i].image = images[i];
        initCount += 1;
    }
    std.debug.print("Swapchain Image Buckets: {}\n", .{buckets.len});
    return buckets;
}
