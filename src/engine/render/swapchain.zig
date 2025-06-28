const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const SwapBucket = @import("SwapBucket.zig").SwapBucket;
const RenderImage = @import("ResourceManager.zig").RenderImage;
const VkAllocator = @import("../vma.zig").VkAllocator;
const createSwapBuckets = @import("SwapBucket.zig").createSwapBuckets;
const getSurfaceCaps = @import("Context.zig").getSurfaceCaps;
const check = @import("../error.zig").check;

pub const Swapchain = struct {
    alloc: Allocator,
    handle: c.VkSwapchainKHR,
    swapBuckets: []SwapBucket,
    index: u32,
    mode: c.VkPresentModeKHR,
    extent: c.VkExtent2D,

    pub fn init(alloc: Allocator, context: *const Context, surface: c.VkSurfaceKHR, initExtent: c.VkExtent2D) !Swapchain {
        const gpi = context.gpi;
        const families = context.families;
        const surfaceFormat = context.surfaceFormat;
        const caps = try getSurfaceCaps(context.gpu, surface);
        std.debug.print("Caps Extent {}x{}\n", .{ caps.maxImageExtent.width, caps.maxImageExtent.height });

        const mode = c.VK_PRESENT_MODE_IMMEDIATE_KHR; //try context.pickPresentMode();
        const extent = pickExtent(&caps, initExtent);

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
            .imageUsage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
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

        return .{
            .alloc = alloc,
            .handle = handle,
            .index = undefined,
            .mode = mode,
            .extent = extent,
            .swapBuckets = swapBuckets,
        };
    }

    pub fn deinit(self: *Swapchain, gpi: c.VkDevice) void {
        for (0..self.swapBuckets.len) |i| {
            self.swapBuckets[i].deinit(gpi);
        }
        self.alloc.free(self.swapBuckets);
        c.vkDestroySwapchainKHR(gpi, self.handle, null);
    }

    pub fn getCurrentRenderSemaphore(self: *Swapchain) c.VkSemaphore {
        return self.swapBuckets[self.index].rendSem;
    }

    pub fn acquireImage(self: *Swapchain, gpi: c.VkDevice, acqSem: c.VkSemaphore) !void {
        const acquireResult = c.vkAcquireNextImageKHR(gpi, self.handle, 1_000_000_000, acqSem, null, &self.index);
        if (acquireResult == c.VK_ERROR_OUT_OF_DATE_KHR or acquireResult == c.VK_SUBOPTIMAL_KHR) return error.NeedNewSwapchain;
        try check(acquireResult, "could not acquire next image");
    }

    pub fn present(self: *Swapchain, pQueue: c.VkQueue) !void {
        const presentInf = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.swapBuckets[self.index].rendSem,
            .swapchainCount = 1,
            .pSwapchains = &self.handle,
            .pImageIndices = &self.index,
        };
        const result = c.vkQueuePresentKHR(pQueue, &presentInf);
        if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR) return error.NeedNewSwapchain;
        try check(result, "could not present queue");
    }
};

fn pickExtent(caps: *const c.VkSurfaceCapabilitiesKHR, curExtent: c.VkExtent2D) c.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32)) return caps.currentExtent;
    return c.VkExtent2D{
        .width = std.math.clamp(curExtent.width, caps.minImageExtent.width, caps.maxImageExtent.width),
        .height = std.math.clamp(curExtent.height, caps.minImageExtent.height, caps.maxImageExtent.height),
    };
}
