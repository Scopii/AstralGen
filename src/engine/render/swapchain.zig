const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const SwapBucket = @import("SwapBucket.zig").SwapBucket;
const Frame = @import("../sync/FramePacer.zig").Frame;
const RenderImage = @import("RenderImage.zig").RenderImage;
const VkAllocator = @import("../vma.zig").VkAllocator;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const createSwapBuckets = @import("SwapBucket.zig").createSwapBuckets;
const check = @import("../error.zig").check;

pub const Swapchain = struct {
    alloc: Allocator,
    handle: c.VkSwapchainKHR,
    swapBuckets: []SwapBucket,
    surfaceFormat: c.VkSurfaceFormatKHR,
    mode: c.VkPresentModeKHR,
    extent: c.VkExtent2D,
    renderImage: RenderImage,

    pub fn init(resourceMan: *const ResourceManager, alloc: Allocator, context: *const Context, curExtent: *const c.VkExtent2D) !Swapchain {
        const gpi = context.gpi;
        const gpu = context.gpu;
        const families = context.families;
        const surface = context.surface;

        // Get surface capabilities
        var caps: c.VkSurfaceCapabilitiesKHR = undefined;
        try check(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &caps), "Failed to get surface capabilities");

        // Pick surface format directly
        const surfaceFormat = try pickSurfaceFormat(alloc, gpu, surface);
        const mode = c.VK_PRESENT_MODE_IMMEDIATE_KHR; //try pickPresentMode(alloc, gpu, surface);
        const extent = pickExtent(&caps, curExtent);

        // Calculate image count
        var desiredImgCount: u32 = caps.minImageCount + 1;
        if (caps.maxImageCount > 0 and desiredImgCount > caps.maxImageCount) {
            desiredImgCount = caps.maxImageCount;
        }

        // Set up sharing mode
        var sharingMode: c.VkSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        var familyIndices: [2]u32 = undefined;
        var familyCount: u32 = 0;

        if (families.graphics != families.present) {
            sharingMode = c.VK_SHARING_MODE_CONCURRENT;
            familyIndices[0] = families.graphics;
            familyIndices[1] = families.present;
            familyCount = 2;
        }

        const swapchainInf = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface,
            .minImageCount = desiredImgCount,
            .imageFormat = surfaceFormat.format,
            .imageColorSpace = surfaceFormat.colorSpace,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_STORAGE_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = sharingMode,
            .queueFamilyIndexCount = familyCount,
            .pQueueFamilyIndices = if (familyCount > 0) &familyIndices else null,
            .preTransform = caps.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = mode,
            .clipped = c.VK_TRUE,
        };

        var handle: c.VkSwapchainKHR = undefined;
        try check(c.vkCreateSwapchainKHR(gpi, &swapchainInf, null, &handle), "Could not create swapchain");

        var realImgCount: u32 = 0;
        try check(c.vkGetSwapchainImagesKHR(gpi, handle, &realImgCount, null), "Could not get swapchain images");
        const swapBuckets = try createSwapBuckets(alloc, realImgCount, gpi, handle, surfaceFormat.format);

        // GPU COMPUTE DRWAING THINGS //
        const renderImage = try resourceMan.createRenderImage(extent);

        return .{
            .alloc = alloc,
            .handle = handle,
            .surfaceFormat = surfaceFormat,
            .mode = mode,
            .extent = extent,
            .swapBuckets = swapBuckets,
            .renderImage = renderImage,
        };
    }

    pub fn deinit(self: *Swapchain, gpi: c.VkDevice, resourceMan: *const ResourceManager) void {
        resourceMan.destroyRenderImage(self.renderImage);

        for (0..self.swapBuckets.len) |i| {
            self.swapBuckets[i].deinit(gpi);
        }
        self.alloc.free(self.swapBuckets);
        c.vkDestroySwapchainKHR(gpi, self.handle, null);
    }

    pub fn acquireImage(self: *Swapchain, gpi: c.VkDevice, frame: *Frame) !bool {
        const acquireResult = c.vkAcquireNextImageKHR(gpi, self.handle, 1_000_000_000, frame.acqSem, null, &frame.index);
        if (acquireResult == c.VK_ERROR_OUT_OF_DATE_KHR or acquireResult == c.VK_SUBOPTIMAL_KHR) {
            return false;
        }
        try check(acquireResult, "could not acquire next image");
        return true;
    }

    pub fn present(self: *Swapchain, pQueue: c.VkQueue, frame: *Frame) !bool {
        const presentInfo = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.swapBuckets[frame.index].rendSem,
            .swapchainCount = 1,
            .pSwapchains = &self.handle,
            .pImageIndices = &frame.index,
        };

        const result = c.vkQueuePresentKHR(pQueue, &presentInfo);

        // Return true if swapchain needs recreation
        if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR) {
            return true;
        }

        // Check for other errors
        try check(result, "could not present queue");
        return false; // No recreation needed
    }
};

// Simplified helper functions that query what they need directly
fn pickSurfaceFormat(alloc: Allocator, gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkSurfaceFormatKHR {
    var formatCount: u32 = 0;
    try check(c.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, null), "Failed to get format count");

    if (formatCount == 0) return error.NoSurfaceFormats;

    const formats = try alloc.alloc(c.VkSurfaceFormatKHR, formatCount);
    defer alloc.free(formats);

    try check(c.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, formats.ptr), "Failed to get surface formats");

    // Return preferred format if available, otherwise first one
    if (formats.len == 1 and formats[0].format == c.VK_FORMAT_UNDEFINED) {
        return c.VkSurfaceFormatKHR{ .format = c.VK_FORMAT_B8G8R8A8_UNORM, .colorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR };
    }

    for (formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_UNORM and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return format;
        }
    }
    return formats[0];
}

fn pickPresentMode(alloc: Allocator, gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkPresentModeKHR {
    var modeCount: u32 = 0;
    try check(c.vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &modeCount, null), "Failed to get present mode count");

    if (modeCount == 0) return c.VK_PRESENT_MODE_FIFO_KHR; // FIFO is always supported

    const modes = try alloc.alloc(c.VkPresentModeKHR, modeCount);
    defer alloc.free(modes);

    try check(c.vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &modeCount, modes.ptr), "Failed to get present modes");

    // Prefer mailbox (triple buffering), then immediate, fallback to FIFO
    for (modes) |mode| {
        if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) return mode;
    }
    for (modes) |mode| {
        if (mode == c.VK_PRESENT_MODE_IMMEDIATE_KHR) return mode;
    }
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn pickExtent(caps: *const c.VkSurfaceCapabilitiesKHR, currExtent: *const c.VkExtent2D) c.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32)) return caps.currentExtent;

    return c.VkExtent2D{
        .width = std.math.clamp(currExtent.width, caps.minImageExtent.width, caps.maxImageExtent.width),
        .height = std.math.clamp(currExtent.height, caps.minImageExtent.height, caps.maxImageExtent.height),
    };
}
