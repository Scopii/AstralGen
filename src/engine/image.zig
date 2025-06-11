const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;
const createSemaphore = @import("sync.zig").createSemaphore;

pub const Image = struct {
    handle: c.VkImage,
    view: c.VkImageView,
    rendSem: c.VkSemaphore,
};

pub const ImageBucket = struct {
    images: []Image,

    pub fn init(alloc: Allocator, imgCount: u32, gpi: c.VkDevice, swapchain: c.VkSwapchainKHR, format: c.VkFormat) !ImageBucket {
        var count = imgCount;
        const handles: []c.VkImage = try createImages(alloc, gpi, swapchain, &count);
        const imgViews: []c.VkImageView = try createImageViews(alloc, gpi, handles, format);

        const rendSems = try alloc.alloc(c.VkSemaphore, count);
        errdefer alloc.free(rendSems);

        for (0..imgCount) |i| {
            rendSems[i] = createSemaphore(gpi) catch |err| {
                // Cleanup on error
                for (0..i) |j| {
                    c.vkDestroySemaphore(gpi, rendSems[j], null);
                }
                return err;
            };
        }

        var images = try alloc.alloc(Image, imgCount);

        for (0..imgCount) |i| {
            images[i].handle = handles[i];
            images[i].view = imgViews[i];
            images[i].rendSem = rendSems[i];
        }

        alloc.free(handles); // Add this
        alloc.free(imgViews); // Add this
        alloc.free(rendSems); // Add this

        return .{
            .images = images,
        };
    }

    pub fn deinit(self: *ImageBucket, alloc: Allocator, gpi: c.VkDevice) void {
        for (0..self.images.len) |i| {
            c.vkDestroyImageView(gpi, self.images[i].view, null);
            c.vkDestroySemaphore(gpi, self.images[i].rendSem, null);
        }
        alloc.free(self.images);
    }
};

fn createImages(alloc: Allocator, gpi: c.VkDevice, swapchain: c.VkSwapchainKHR, imgCount: *u32) ![]c.VkImage {
    if (imgCount.* == 0) try check(c.vkGetSwapchainImagesKHR(gpi, swapchain, imgCount, null), "Could not get Swapchain Images");
    const images = try alloc.alloc(c.VkImage, imgCount.*);

    const result = c.vkGetSwapchainImagesKHR(gpi, swapchain, imgCount, images.ptr);
    if (result != c.VK_SUCCESS) {
        alloc.free(images);
        return error.FailedToCreateSwapchainImages;
    }
    return images;
}

fn createImageViews(alloc: Allocator, gpi: c.VkDevice, images: []c.VkImage, format: c.VkFormat) ![]c.VkImageView {
    const imgViews = try alloc.alloc(c.VkImageView, images.len);
    errdefer alloc.free(imgViews);

    for (images, 0..) |image, i| {
        const imgViewInf = c.VkImageViewCreateInfo{
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

        const success = c.vkCreateImageView(gpi, &imgViewInf, null, &imgViews[i]);
        if (success != c.VK_SUCCESS) {
            // Clean up
            for (0..i) |j| {
                c.vkDestroyImageView(gpi, imgViews[j], null);
            }
            return error.ImageViewCreationFailed;
        }
    }
    return imgViews;
}
