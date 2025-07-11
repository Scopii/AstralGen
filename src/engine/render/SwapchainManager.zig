const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const check = @import("../error.zig").check;
const createSemaphore = @import("../sync/primitives.zig").createSemaphore;
const PipelineType = @import("../render/PipelineBucket.zig").PipelineType;
const Window = @import("../../core/Window.zig").Window;

const MAX_IN_FLIGHT = @import("../Renderer.zig").MAX_IN_FLIGHT;
const MAX_SWAPCHAINS_PER_PASS = 3;

pub const Swapchain = struct {
    surface: c.VkSurfaceKHR,
    handle: c.VkSwapchainKHR,
    extent: c.VkExtent2D,
    images: []c.VkImage,
    views: []c.VkImageView,
    imageRdySemaphores: []c.VkSemaphore, // indexed by max-in-flight.
    renderDoneSemaphores: []c.VkSemaphore, // indexed by swapchain images
    surfaceFormat: c.VkSurfaceFormatKHR,
    pipeType: PipelineType,
};

pub const SwapchainManager = struct {
    alloc: Allocator,
    gpi: c.VkDevice,
    instance: c.VkInstance,

    pub fn init(alloc: Allocator, context: *const Context) !SwapchainManager {
        return .{
            .alloc = alloc,
            .gpi = context.gpi,
            .instance = context.instance,
        };
    }

    pub fn deinit(_: *SwapchainManager) void {}

    pub fn addSwapchain(self: *SwapchainManager, context: *const Context, window: *Window, oldHandle: ?c.VkSwapchainKHR, pipeType: PipelineType, extent: c.VkExtent2D) !void {
        const alloc = self.alloc;
        const gpi = self.gpi;
        const families = context.families;
        const gpu = context.gpu;

        const surface = if (oldHandle != null) window.swapchain.?.surface else try createSurface(window.handle, self.instance);
        const surfaceFormat = try pickSurfaceFormat(alloc, gpu, surface);
        const caps = try getSurfaceCaps(gpu, surface);
        const mode = c.VK_PRESENT_MODE_IMMEDIATE_KHR; //try context.pickPresentMode();

        var desiredImgCount: u32 = caps.minImageCount + 1;
        if (caps.maxImageCount > 0 and desiredImgCount > caps.maxImageCount) desiredImgCount = caps.maxImageCount;

        var sharingMode: c.VkSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        var familyIndices: [2]u32 = undefined;
        var familyCount: u32 = 0;

        if (families.graphics != families.present) {
            sharingMode = c.VK_SHARING_MODE_CONCURRENT;
            familyIndices[0] = families.graphics;
            familyIndices[1] = families.present;
            familyCount = 2;
        }

        const actualExtent = pickExtent(&caps, extent);

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
            .oldSwapchain = oldHandle orelse null,
        };

        var handle: c.VkSwapchainKHR = undefined;
        try check(c.vkCreateSwapchainKHR(gpi, &swapchainInf, null, &handle), "Could not create Swapchain Handle");

        var realImgCount: u32 = 0;
        _ = c.vkGetSwapchainImagesKHR(gpi, handle, &realImgCount, null);

        const images = try alloc.alloc(c.VkImage, realImgCount);
        errdefer alloc.free(images);
        try check(c.vkGetSwapchainImagesKHR(gpi, handle, &realImgCount, images.ptr), "Could not get Swapchain Images");

        const views = try alloc.alloc(c.VkImageView, realImgCount);
        errdefer alloc.free(views);

        for (0..realImgCount) |i| {
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
        }

        const imageRdySems = try alloc.alloc(c.VkSemaphore, MAX_IN_FLIGHT);
        errdefer alloc.free(imageRdySems);
        for (0..MAX_IN_FLIGHT) |i| imageRdySems[i] = try createSemaphore(gpi);

        const renderDoneSems = try alloc.alloc(c.VkSemaphore, realImgCount);
        errdefer alloc.free(renderDoneSems);
        for (0..realImgCount) |i| renderDoneSems[i] = try createSemaphore(gpi);

        if (oldHandle != null) self.destroySwapchainNotSurface(window);

        const newSwapchain = Swapchain{
            .surface = surface,
            .surfaceFormat = surfaceFormat,
            .extent = actualExtent,
            .handle = handle,
            .images = images,
            .views = views,
            .imageRdySemaphores = imageRdySems,
            .renderDoneSemaphores = renderDoneSems,
            .pipeType = pipeType,
        };
        window.swapchain = newSwapchain;
        window.status = .active;
        std.debug.print("Swapchain added to Window {}\n", .{window.id});
    }

    pub fn pickSurfaceFormat(alloc: Allocator, gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkSurfaceFormatKHR {
        var formatCount: u32 = 0;
        try check(c.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, null), "Failed to get format count");
        if (formatCount == 0) return error.NoSurfaceFormats;

        const formats = try alloc.alloc(c.VkSurfaceFormatKHR, formatCount);
        defer alloc.free(formats);

        try check(c.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, formats.ptr), "Failed to get surface formats");

        // Return preferred format if available otherwise first one
        if (formats.len == 1 and formats[0].format == c.VK_FORMAT_UNDEFINED) {
            return c.VkSurfaceFormatKHR{ .format = c.VK_FORMAT_B8G8R8A8_UNORM, .colorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR };
        }

        for (formats) |format| {
            if (format.format == c.VK_FORMAT_B8G8R8A8_UNORM and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) return format;
        }
        return formats[0];
    }

    pub fn destroySwapchain(self: *SwapchainManager, window: *Window) void {
        const gpi = self.gpi;

        if (window.swapchain) |*sc| {
            for (sc.views) |view| c.vkDestroyImageView(gpi, view, null);
            for (sc.imageRdySemaphores) |sem| c.vkDestroySemaphore(gpi, sem, null);
            for (sc.renderDoneSemaphores) |sem| c.vkDestroySemaphore(gpi, sem, null);
            c.vkDestroySwapchainKHR(gpi, sc.handle, null);
            c.vkDestroySurfaceKHR(self.instance, sc.surface, null);

            self.alloc.free(sc.images);
            self.alloc.free(sc.views);
            self.alloc.free(sc.imageRdySemaphores);
            self.alloc.free(sc.renderDoneSemaphores);

            window.swapchain = null;
            std.debug.print("Swapchain destroyed\n", .{});
        } else std.debug.print("Cant Swapchain to destroy missing.\n", .{});
    }

    pub fn destroySwapchainNotSurface(self: *SwapchainManager, window: *Window) void {
        const gpi = self.gpi;

        if (window.swapchain) |*sc| {
            for (sc.views) |view| c.vkDestroyImageView(gpi, view, null);
            for (sc.imageRdySemaphores) |sem| c.vkDestroySemaphore(gpi, sem, null);
            for (sc.renderDoneSemaphores) |sem| c.vkDestroySemaphore(gpi, sem, null);
            c.vkDestroySwapchainKHR(gpi, sc.handle, null);

            self.alloc.free(sc.images);
            self.alloc.free(sc.views);
            self.alloc.free(sc.imageRdySemaphores);
            self.alloc.free(sc.renderDoneSemaphores);

            window.swapchain = null;
            std.debug.print("Swapchain destroyed\n", .{});
        } else std.debug.print("Cant Swapchain to destroy missing.\n", .{});
    }

    pub fn findSwapchainId(self: *SwapchainManager, windowId: u32) !u32 {
        for (0..self.swapchains.items.len) |i| {
            if (self.swapchains.items[i].window.id == windowId) return @intCast(i);
        }
        return error.SwapchainDoesNotExist;
    }

    pub fn getSwapchainExtent(self: *SwapchainManager, windowId: u32) !c.VkExtent2D {
        const arrayId = try self.findSwapchainId(windowId);
        const swapchain = &self.swapchains.items[arrayId];
        return swapchain.extent;
    }

    pub fn getSwapchainsCount(self: *SwapchainManager) u32 {
        return @intCast(self.swapchains.items.len);
    }
};

fn getSurfaceCaps(gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkSurfaceCapabilitiesKHR {
    var caps: c.VkSurfaceCapabilitiesKHR = undefined;
    try check(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &caps), "Failed to get surface capabilities");
    return caps;
}

fn createSurface(window: *c.SDL_Window, instance: c.VkInstance) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    if (c.SDL_Vulkan_CreateSurface(window, @ptrCast(instance), null, @ptrCast(&surface)) == false) {
        std.log.err("Unable to create Vulkan surface: {s}\n", .{c.SDL_GetError()});
        return error.VkSurface;
    }
    return surface;
}

fn pickExtent(caps: *const c.VkSurfaceCapabilitiesKHR, curExtent: c.VkExtent2D) c.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32)) return caps.currentExtent;
    return c.VkExtent2D{
        .width = std.math.clamp(curExtent.width, caps.minImageExtent.width, caps.maxImageExtent.width),
        .height = std.math.clamp(curExtent.height, caps.minImageExtent.height, caps.maxImageExtent.height),
    };
}
