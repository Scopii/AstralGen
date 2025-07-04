const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const check = @import("../error.zig").check;
const createSemaphore = @import("../sync/primitives.zig").createSemaphore;
const PipelineType = @import("../render/PipelineBucket.zig").PipelineType;
const MAX_IN_FLIGHT = @import("../Renderer.zig").MAX_IN_FLIGHT;
const VulkanWindow = @import("../../core/VulkanWindow.zig").VulkanWindow;

pub const SwapchainManager = struct {
    pub const Swapchain = struct {
        window: *const VulkanWindow,
        surface: c.VkSurfaceKHR,
        handle: c.VkSwapchainKHR,
        images: []c.VkImage,
        views: []c.VkImageView,
        imageRdySemaphores: []c.VkSemaphore, // indexed by frame-in-flight.
        renderDoneSemaphores: []c.VkSemaphore, // indexed by swapchain image index
        surfaceFormat: c.VkSurfaceFormatKHR,
    };
    alloc: Allocator,
    gpi: c.VkDevice,
    instance: c.VkInstance,
    swapchains: std.ArrayList(Swapchain),

    pub fn init(alloc: Allocator, context: *const Context) !SwapchainManager {
        return .{
            .alloc = alloc,
            .swapchains = std.ArrayList(Swapchain).init(alloc),
            .gpi = context.gpi,
            .instance = context.instance,
        };
    }

    pub fn deinit(self: *SwapchainManager) void {
        for (self.swapchains.items.len..0) |i| self.destroySwapchain(self.swapchains.items[i].window.id) catch {
            std.debug.print("Could not destroy all Swapchains", .{});
        };
        self.swapchains.deinit();
    }

    pub fn addSwapchain(self: *SwapchainManager, context: *const Context, vulkanWindow: *const VulkanWindow) !void {
        const alloc = self.alloc;
        const gpi = self.gpi;
        const families = context.families;
        const gpu = context.gpu;
        const instance = context.instance;

        const surface = try createSurface(vulkanWindow.handle, instance);
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

        const swapchainInf = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface,
            .minImageCount = desiredImgCount,
            .imageFormat = surfaceFormat.format,
            .imageColorSpace = surfaceFormat.colorSpace,
            .imageExtent = pickExtent(&caps, vulkanWindow.extent),
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

        std.debug.print("Swapchain {} Window {} ({} Images)\n", .{ self.swapchains.items.len, vulkanWindow.id, realImgCount });

        const newSwapchain = Swapchain{
            .window = vulkanWindow,
            .surface = surface,
            .surfaceFormat = surfaceFormat,
            .handle = handle,
            .images = images,
            .views = views,
            .imageRdySemaphores = imageRdySems,
            .renderDoneSemaphores = renderDoneSems,
        };
        try self.swapchains.append(newSwapchain);
    }

    pub fn pickSurfaceFormat(alloc: Allocator, gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkSurfaceFormatKHR {
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

    pub fn destroySwapchain(self: *SwapchainManager, windowId: u32) !void {
        const gpi = self.gpi;
        const arrayId = try self.findSwapchainId(windowId);
        const swapchain = &self.swapchains.items[arrayId];

        for (swapchain.views) |view| c.vkDestroyImageView(gpi, view, null);
        for (swapchain.imageRdySemaphores) |sem| c.vkDestroySemaphore(gpi, sem, null);
        for (swapchain.renderDoneSemaphores) |sem| c.vkDestroySemaphore(gpi, sem, null);
        c.vkDestroySwapchainKHR(gpi, swapchain.handle, null);
        c.vkDestroySurfaceKHR(self.instance, swapchain.surface, null);

        self.alloc.free(swapchain.images);
        self.alloc.free(swapchain.views);
        self.alloc.free(swapchain.imageRdySemaphores);
        self.alloc.free(swapchain.renderDoneSemaphores);
        _ = self.swapchains.swapRemove(arrayId);
        std.debug.print("Swapchain {} destroyed\n", .{arrayId});
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
