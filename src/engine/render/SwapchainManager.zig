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
const createSemaphore = @import("../sync/primitives.zig").createSemaphore;

pub const Swapchain = struct {
    windowId: u32,
    surface: c.VkSurfaceKHR,
    handle: c.VkSwapchainKHR,
    extent: c.VkExtent2D,
    images: []c.VkImage,
    views: []c.VkImageView,
    imageRdySemaphore: []c.VkSemaphore,
    //imageFormat: c.VkFormat,
};

pub const SwapchainManager = struct {
    alloc: Allocator,
    gpi: c.VkDevice,
    swapchains: std.ArrayList(Swapchain),

    pub fn init(alloc: Allocator, gpi: c.VkDevice) !SwapchainManager {
        return .{
            .alloc = alloc,
            .swapchains = std.ArrayList(Swapchain).init(alloc),
            .gpi = gpi,
        };
    }

    pub fn deinit(self: *SwapchainManager) void {
        for (0..self.swapchains.items.len) |i| {
            destroySwapchain(i);
        }
        self.swapchains.deinit();
    }

    pub fn addSwapchain(self: *SwapchainManager, context: *const Context, surface: c.VkSurfaceKHR, extent: c.VkExtent2D, windowId: u32) !void {
        const alloc = self.alloc;
        const gpi = self.gpi;

        const families = context.families;
        const surfaceFormat = context.surfaceFormat;
        const caps = try getSurfaceCaps(context.gpu, surface);
        std.debug.print("Caps Extent {}x{}\n", .{ caps.maxImageExtent.width, caps.maxImageExtent.height });

        const mode = c.VK_PRESENT_MODE_IMMEDIATE_KHR; //try context.pickPresentMode();
        const actualExtent = pickExtent(&caps, extent);

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
        try check(c.vkCreateSwapchainKHR(gpi, &swapchainInf, null, &handle), "Could not create Swapchain Handle");

        var realImgCount: u32 = 0;
        try check(c.vkGetSwapchainImagesKHR(gpi, handle, &realImgCount, null), "Could not get Swapchain Image Count");

        const images = try alloc.alloc(c.VkImage, realImgCount);
        defer alloc.free(images); // Managed by Swapchain
        try check(c.vkGetSwapchainImagesKHR(gpi, handle, &realImgCount, images.ptr), "Could not get Swapchain Images");

        const views = try alloc.alloc(c.VkImageView, realImgCount);
        errdefer alloc.free(views); // Free if anything fails below

        const imageRdySemaphores = try alloc.alloc(c.VkSemaphore, realImgCount);
        errdefer alloc.free(imageRdySemaphores); // Free if anything fails below

        var initCount: u32 = 0;
        errdefer { // Clean up partially created resources
            for (0..initCount) |i| {
                if (views[i] != null) c.vkDestroyImageView(gpi, views[i], null);
                if (imageRdySemaphores[i] != null) c.vkDestroySemaphore(gpi, imageRdySemaphores[i], null);
            }
        }

        for (0..realImgCount) |i| {
            // Create image view
            const imgViewInf = c.VkImageViewCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = images[i],
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = surfaceFormat.format,
                .subresourceRange = c.VkImageSubresourceRange{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };
            try check(c.vkCreateImageView(gpi, &imgViewInf, null, &views[i]), "Failed to create image view");

            imageRdySemaphores[i] = try createSemaphore(gpi);
            initCount += 1;
        }
        std.debug.print("Swapchain {} Members {}\n", .{ self.swapchains.items.len, realImgCount });

        const newSwapchain = Swapchain{
            .windowId = windowId,
            .surface = surface,
            .handle = handle,
            .extent = extent,
            .images = images,
            .views = views,
            .imageRdySemaphore = imageRdySemaphores,
        };

        self.swapchains.append(newSwapchain);
    }

    pub fn destroySwapchain(self: *SwapchainManager, number: u32) void {
        const gpi = self.gpi;
        const swapchain = &self.swapchains.items[number];

        for (swapchain.views) |view| {
            c.vkDestroyImageView(gpi, view, null);
        }
        for (swapchain.imageRdySemaphore) |semaphore| {
            c.vkDestroySemaphore(gpi, semaphore, null);
        }
        c.vkDestroySwapchainKHR(gpi, swapchain.swapchains.items, null);
    }
};

fn pickExtent(caps: *const c.VkSurfaceCapabilitiesKHR, curExtent: c.VkExtent2D) c.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32)) return caps.currentExtent;
    return c.VkExtent2D{
        .width = std.math.clamp(curExtent.width, caps.minImageExtent.width, caps.maxImageExtent.width),
        .height = std.math.clamp(curExtent.height, caps.minImageExtent.height, caps.maxImageExtent.height),
    };
}
