const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const RenderImage = @import("ResourceManager.zig").RenderImage;
const VkAllocator = @import("../vma.zig").VkAllocator;
const getSurfaceCaps = @import("Context.zig").getSurfaceCaps;
const check = @import("../error.zig").check;
const createSemaphore = @import("../sync/primitives.zig").createSemaphore;
const PipelineType = @import("../render/PipelineBucket.zig").PipelineType;

pub const SwapchainManager = struct {
    pub const Swapchain = struct {
        windowId: u32,
        surface: c.VkSurfaceKHR,
        handle: c.VkSwapchainKHR,
        extent: c.VkExtent2D,
        pipeType: PipelineType,
        images: []c.VkImage,
        views: []c.VkImageView,
        imageRdySemaphore: []c.VkSemaphore,
        renderDoneSemaphore: []c.VkSemaphore,
        //imageFormat: c.VkFormat, later!
    };
    alloc: Allocator,
    gpi: c.VkDevice,
    instance: c.VkInstance,
    maxInFlight: u8,
    swapchains: std.ArrayList(Swapchain),

    pub fn init(alloc: Allocator, context: *const Context, maxInFlight: u8) !SwapchainManager {
        return .{
            .alloc = alloc,
            .swapchains = std.ArrayList(Swapchain).init(alloc),
            .gpi = context.gpi,
            .maxInFlight = maxInFlight,
            .instance = context.instance,
        };
    }

    pub fn deinit(self: *SwapchainManager) void {
        var i = self.swapchains.items.len;
        while (i > 0) {
            i -= 1;
            self.destroySwapchain(self.swapchains.items[i].windowId) catch {};
        }
        self.swapchains.deinit();
    }

    pub fn addSwapchain(self: *SwapchainManager, context: *const Context, surface: c.VkSurfaceKHR, extent: c.VkExtent2D, windowId: u32, pipeType: PipelineType) !void {
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
            .imageExtent = actualExtent,
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
        try check(c.vkGetSwapchainImagesKHR(gpi, handle, &realImgCount, images.ptr), "Could not get Swapchain Images");

        const views = try alloc.alloc(c.VkImageView, realImgCount);

        var initCount: u32 = 0;
        errdefer { // Clean up partially created resources
            for (0..initCount) |i| {
                if (views[i] != null) c.vkDestroyImageView(gpi, views[i], null);
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
            initCount += 1;
        }
        std.debug.print("Swapchain {} Members {}\n", .{ self.swapchains.items.len, realImgCount });

        const imageRdySemaphores = try alloc.alloc(c.VkSemaphore, realImgCount);
        errdefer alloc.free(imageRdySemaphores);

        const renderDoneSemaphore = try alloc.alloc(c.VkSemaphore, realImgCount);
        errdefer alloc.free(renderDoneSemaphore);

        for (0..realImgCount) |i| {
            imageRdySemaphores[i] = try createSemaphore(gpi);
            renderDoneSemaphore[i] = try createSemaphore(gpi);
        }

        const newSwapchain = Swapchain{
            .windowId = windowId,
            .surface = surface,
            .handle = handle,
            .extent = extent,
            .images = images,
            .views = views,
            .imageRdySemaphore = imageRdySemaphores,
            .renderDoneSemaphore = renderDoneSemaphore,
            .pipeType = pipeType,
        };

        try self.swapchains.append(newSwapchain);
    }

    pub fn destroySwapchain(self: *SwapchainManager, windowId: u32) !void {
        const gpi = self.gpi;
        const arrayId = try self.findSwapchainId(windowId);
        const swapchain = &self.swapchains.items[arrayId];

        for (swapchain.views) |view| {
            c.vkDestroyImageView(gpi, view, null);
        }
        for (swapchain.imageRdySemaphore) |semaphore| {
            c.vkDestroySemaphore(gpi, semaphore, null);
        }
        for (swapchain.renderDoneSemaphore) |semaphore| {
            c.vkDestroySemaphore(gpi, semaphore, null);
        }
        c.vkDestroySwapchainKHR(gpi, swapchain.handle, null);
        c.vkDestroySurfaceKHR(self.instance, swapchain.surface, null);

        self.alloc.free(swapchain.images);
        self.alloc.free(swapchain.views);
        self.alloc.free(swapchain.imageRdySemaphore);
        self.alloc.free(swapchain.renderDoneSemaphore);
        _ = self.swapchains.swapRemove(arrayId);
    }

    pub fn getSwapchainExtent(self: *SwapchainManager, windowId: u32) !c.VkExtent2D {
        const arrayId = try self.findSwapchainId(windowId);
        const swapchain = &self.swapchains.items[arrayId];
        return swapchain.extent;
    }

    pub fn getSwapchainsCount(self: *SwapchainManager) u32 {
        return @intCast(self.swapchains.items.len);
    }

    pub fn findSwapchainId(self: *SwapchainManager, windowId: u32) !u32 {
        for (0..self.swapchains.items.len) |i| {
            if (self.swapchains.items[i].windowId == windowId) return @intCast(i);
        }
        return error.SwapchainDoesNotExist;
    }
};

fn pickExtent(caps: *const c.VkSurfaceCapabilitiesKHR, curExtent: c.VkExtent2D) c.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32)) return caps.currentExtent;
    return c.VkExtent2D{
        .width = std.math.clamp(curExtent.width, caps.minImageExtent.width, caps.maxImageExtent.width),
        .height = std.math.clamp(curExtent.height, caps.minImageExtent.height, caps.maxImageExtent.height),
    };
}
