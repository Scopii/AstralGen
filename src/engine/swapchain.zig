const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;

// Import QueueFamilies from device.zig
const QueueFamilies = @import("device.zig").QueueFamilies;

pub const Swapchain = struct {
    alloc: Allocator,
    handle: c.VkSwapchainKHR,
    surfaceFormat: c.VkSurfaceFormatKHR,
    mode: c.VkPresentModeKHR,
    extent: c.VkExtent2D,
    images: []c.VkImage = undefined,
    imageViews: []c.VkImageView = undefined,
    imageCount: u32 = undefined,

    pub fn init(alloc: Allocator, device: c.VkDevice, gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, current_extent: c.VkExtent2D, queue_families: QueueFamilies) !Swapchain {
        var details = try checkSwapchainSupport(alloc, gpu, surface); // Get swapchain support details
        defer details.deinit(); // Clean up details after use

        const surfaceFormat = try pickSurfaceFormat(details);
        const mode = pickPresentMode(details);
        const extent = pickExtent(details.capabilities, current_extent);

        // Create swapchain
        var image_count = details.capabilities.minImageCount + 1;
        if (details.capabilities.maxImageCount > 0 and image_count > details.capabilities.maxImageCount) {
            image_count = details.capabilities.maxImageCount; // Clamp to max if exists
        }

        var sharing_mode: c.VkSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        var queue_family_indices: [2]u32 = undefined;
        var queue_family_count: u32 = 0;

        if (queue_families.graphics != queue_families.present) {
            sharing_mode = c.VK_SHARING_MODE_CONCURRENT; // Need concurrent access
            queue_family_indices[0] = queue_families.graphics;
            queue_family_indices[1] = queue_families.present;
            queue_family_count = 2;
        }

        const create_info = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .pNext = null,
            .flags = 0,
            .surface = surface,
            .minImageCount = image_count,
            .imageFormat = surfaceFormat.format,
            .imageColorSpace = surfaceFormat.colorSpace,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = sharing_mode,
            .queueFamilyIndexCount = queue_family_count,
            .pQueueFamilyIndices = if (queue_family_count > 0) &queue_family_indices else null,
            .preTransform = details.capabilities.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = mode,
            .clipped = c.VK_TRUE,
            .oldSwapchain = null,
        };

        var handle: c.VkSwapchainKHR = undefined;
        const result = c.vkCreateSwapchainKHR(device, &create_info, null, &handle);
        if (result != c.VK_SUCCESS) {
            return error.SwapchainCreationFailed;
        }

        var imageCount: u32 = 0;
        _ = c.vkGetSwapchainImagesKHR(device, handle, &imageCount, null);
        const images: []c.VkImage = try createImages(alloc, device, handle, &imageCount);
        const imageViews: []c.VkImageView = try createImageViews(alloc, device, images, surfaceFormat.format);

        return .{ .alloc = alloc, .handle = handle, .surfaceFormat = surfaceFormat, .mode = mode, .extent = extent, .imageCount = imageCount, .images = images, .imageViews = imageViews };
    }

    pub fn createImages(alloc: Allocator, device: c.VkDevice, swapchain: c.VkSwapchainKHR, image_count: *u32) ![]c.VkImage {
        // First get the actual count if not provided
        if (image_count.* == 0) {
            const result = c.vkGetSwapchainImagesKHR(device, swapchain, image_count, null);
            if (result != c.VK_SUCCESS) {
                return error.FailedToGetImageCount;
            }
        }

        const images = try alloc.alloc(c.VkImage, image_count.*);
        const result = c.vkGetSwapchainImagesKHR(device, swapchain, image_count, images.ptr);
        if (result != c.VK_SUCCESS) {
            alloc.free(images);
            return error.FailedToCreateSwapchainImages; // Use proper error instead of panic
        }

        return images;
    }

    pub fn deinit(self: *Swapchain, device: c.VkDevice) void {
        // Destroy image views first
        for (self.imageViews) |view| {
            c.vkDestroyImageView(device, view, null);
        }

        self.alloc.free(self.images);
        self.alloc.free(self.imageViews);
        c.vkDestroySwapchainKHR(device, self.handle, null);
    }
};

pub fn createImageViews(alloc: Allocator, device: c.VkDevice, images: []c.VkImage, format: c.VkFormat) ![]c.VkImageView {
    // Allocate array directly instead of using ArrayList
    const image_views = try alloc.alloc(c.VkImageView, images.len);
    errdefer alloc.free(image_views); // Clean up on error

    for (images, 0..) |image, i| { // Use indexed iteration
        const image_view_info = c.VkImageViewCreateInfo{
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

        const success = c.vkCreateImageView(device, &image_view_info, null, &image_views[i]); // Store directly in array
        if (success != c.VK_SUCCESS) {
            // Clean up any image views created so far
            for (0..i) |j| {
                c.vkDestroyImageView(device, image_views[j], null);
            }
            return error.ImageViewCreationFailed; // Return proper error instead of panic
        }
    }

    return image_views;
}

pub const SwapchainDetails = struct {
    arena: std.heap.ArenaAllocator, // Added missing arena field
    capabilities: c.VkSurfaceCapabilitiesKHR = undefined,
    formats: []c.VkSurfaceFormatKHR = undefined,
    present_modes: []c.VkPresentModeKHR = undefined,

    pub fn init(alloc: Allocator) SwapchainDetails {
        return SwapchainDetails{
            .arena = std.heap.ArenaAllocator.init(alloc),
        };
    }

    pub fn deinit(self: *SwapchainDetails) void {
        self.arena.deinit(); // Clean up arena allocator
    }

    // Helper methods for resizing arrays
    pub fn resize_formats(self: *SwapchainDetails, count: u32) !void {
        self.formats = try self.arena.allocator().alloc(c.VkSurfaceFormatKHR, count);
    }

    pub fn resize_present_modes(self: *SwapchainDetails, count: u32) !void {
        self.present_modes = try self.arena.allocator().alloc(c.VkPresentModeKHR, count);
    }
};

pub fn checkSwapchainSupport(alloc: Allocator, gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !SwapchainDetails { // Return SwapchainDetails, not void
    var details = SwapchainDetails.init(alloc);
    errdefer details.deinit(); // Clean up on error

    var result = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &details.capabilities);
    if (result != c.VK_SUCCESS) {
        return error.SwapchainSupportTestFailed;
    }

    var format_count: u32 = 0;
    result = c.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &format_count, null);
    if (result != c.VK_SUCCESS) {
        return error.NoFormat;
    }

    if (format_count != 0) {
        try details.resize_formats(format_count); // Add try keyword
        result = c.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &format_count, details.formats.ptr);
        if (result != c.VK_SUCCESS) {
            return error.NoFormat;
        }
    }

    var present_mode_count: u32 = 0;
    result = c.vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &present_mode_count, null);
    if (result != c.VK_SUCCESS) {
        return error.NoPresentMode;
    }

    if (present_mode_count != 0) {
        try details.resize_present_modes(present_mode_count); // Add try keyword
        result = c.vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &present_mode_count, details.present_modes.ptr);
        if (result != c.VK_SUCCESS) {
            return error.NoPresentMode;
        }
    }

    return details;
}

fn pickSurfaceFormat(details: SwapchainDetails) !c.VkSurfaceFormatKHR {
    if (details.formats.len == 1 and details.formats[0].format == c.VK_FORMAT_UNDEFINED) {
        return c.VkSurfaceFormatKHR{
            .format = c.VK_FORMAT_B8G8R8A8_UNORM, //c.VK_FORMAT_B8G8R8A8_SRGB?
            .colorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
        };
    }

    for (details.formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_UNORM and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return format;
        }
    }

    return details.formats[0];
}

fn pickPresentMode(details: SwapchainDetails) c.VkPresentModeKHR {
    var best_mode: c.VkPresentModeKHR = c.VK_PRESENT_MODE_FIFO_KHR;

    //VK_PRESENT_MODE_IMMEDIATE_KHR     direct
    //VK_PRESENT_MODE_FIFO_KHR          v-sync?
    //VK_PRESENT_MODE_FIFO_RELAXED_KHR  v-sync light?
    //VK_PRESENT_MODE_MAILBOX_KHR       triple buffering (less latency?)

    for (details.present_modes) |mode| {
        if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return mode;
        } else if (mode == c.VK_PRESENT_MODE_IMMEDIATE_KHR) {
            best_mode = mode;
        }
    }

    return best_mode;
}

fn pickExtent(capabilities: c.VkSurfaceCapabilitiesKHR, current_extent: c.VkExtent2D) c.VkExtent2D { // Remove ! - doesn't need to return error
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    }

    const actual_extent = c.VkExtent2D{
        .width = std.math.clamp(current_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
        .height = std.math.clamp(current_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    };

    return actual_extent;
}
