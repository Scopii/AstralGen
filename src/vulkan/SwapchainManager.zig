const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const check = @import("error.zig").check;
const createSemaphore = @import("primitives.zig").createSemaphore;
const PipelineType = @import("PipelineBucket.zig").PipelineType;
const Window = @import("../platform/Window.zig").Window;

const MAX_IN_FLIGHT = @import("../config.zig").MAX_IN_FLIGHT;

pub const Swapchain = struct {
    surface: c.VkSurfaceKHR,
    handle: c.VkSwapchainKHR,
    extent: c.VkExtent2D,
    images: []c.VkImage,
    views: []c.VkImageView,
    curIndex: u32 = 0,
    imageRdySemaphores: []c.VkSemaphore, // indexed by max-in-flight.
    renderDoneSemaphores: []c.VkSemaphore, // indexed by swapchain images
    surfaceFormat: c.VkSurfaceFormatKHR,
    pipeType: PipelineType,
};

pub const SwapchainManager = struct {
    alloc: Allocator,
    gpi: c.VkDevice,
    instance: c.VkInstance,
    renderSize: c.VkExtent2D = .{ .width = 0, .height = 0 },
    swapchains: std.AutoHashMap(u32, Swapchain),
    activeSwapchains: [@typeInfo(PipelineType).@"enum".fields.len]std.ArrayList(*Swapchain),
    targets: std.ArrayList(*Swapchain),

    pub fn init(alloc: Allocator, context: *const Context) !SwapchainManager {
        const enumLength = @typeInfo(PipelineType).@"enum".fields.len;
        var presentTargets: [enumLength]std.ArrayList(*Swapchain) = undefined;
        for (0..enumLength) |i| presentTargets[i] = std.ArrayList(*Swapchain).init(alloc);

        return .{
            .alloc = alloc,
            .gpi = context.gpi,
            .instance = context.instance,
            .swapchains = std.AutoHashMap(u32, Swapchain).init(alloc),
            .activeSwapchains = presentTargets,
            .targets = std.ArrayList(*Swapchain).init(alloc),
        };
    }

    pub fn deinit(self: *SwapchainManager) void {
        self.swapchains.deinit();
        self.targets.deinit();
        for (self.activeSwapchains) |swapchainList| swapchainList.deinit();
    }

    pub fn addSwapchain(self: *SwapchainManager, context: *const Context, window: Window) !void {
        const alloc = self.alloc;
        const gpi = self.gpi;
        const families = context.families;
        const gpu = context.gpu;

        const surface = try createSurface(window.handle, self.instance);
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

        const actualExtent = pickExtent(&caps, window.extent);

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
            //.oldSwapchain = null,
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

        const newSwapchain = Swapchain{
            .surface = surface,
            .surfaceFormat = surfaceFormat,
            .extent = actualExtent,
            .handle = handle,
            .images = images,
            .views = views,
            .imageRdySemaphores = imageRdySems,
            .renderDoneSemaphores = renderDoneSems,
            .pipeType = window.pipeType,
        };
        try self.swapchains.put(window.id, newSwapchain);
        std.debug.print("Swapchain added to Window {}\n", .{window.id});
    }

    pub fn updateTargets(self: *SwapchainManager, frameInFlight: u8, context: *Context) !bool {
        self.targets.clearRetainingCapacity();
        const activeSwapchains = self.activeSwapchains;
        const gpi = self.gpi;

        for (0..activeSwapchains.len) |i| {
            for (activeSwapchains[i].items) |swapchainPtr| {
                const acquireResult = c.vkAcquireNextImageKHR(gpi, swapchainPtr.handle, std.math.maxInt(u64), swapchainPtr.imageRdySemaphores[frameInFlight], null, &swapchainPtr.curIndex);

                switch (acquireResult) {
                    c.VK_SUCCESS => try self.targets.append(swapchainPtr),
                    c.VK_ERROR_OUT_OF_DATE_KHR, c.VK_SUBOPTIMAL_KHR => {
                        try self.recreateSwapchain(swapchainPtr, context);
                        const acquireResult2 = c.vkAcquireNextImageKHR(gpi, swapchainPtr.handle, std.math.maxInt(u64), swapchainPtr.imageRdySemaphores[frameInFlight], null, &swapchainPtr.curIndex);
                        if (acquireResult2 == c.VK_SUCCESS) {
                            try self.targets.append(swapchainPtr);
                            std.debug.print("Resolved Error for Swapchain {}", .{swapchainPtr.*});
                        } else std.debug.print("Could not Resolve Swapchain Error {}", .{swapchainPtr.*});
                    },
                    else => try check(acquireResult, "Could not acquire swapchain image"),
                }
            }
        }
        return if (self.targets.items.len != 0) true else false;
    }

    pub fn updateActiveSwapchains(self: *SwapchainManager, hashKeys: []u32) !void {
        for (0..self.activeSwapchains.len) |i| {
            self.activeSwapchains[i].clearRetainingCapacity();
        }

        var maxWidth: u32 = 0;
        var maxHeight: u32 = 0;

        for (hashKeys) |i| {
            const swapchainPtr = self.getSwapchainPtr(i).?;
            try self.activeSwapchains[@intFromEnum(swapchainPtr.pipeType)].append(swapchainPtr);
            maxWidth = @max(maxWidth, swapchainPtr.extent.width);
            maxHeight = @max(maxHeight, swapchainPtr.extent.height);
        }
        self.renderSize = c.VkExtent2D{ .width = maxWidth, .height = maxHeight };
    }

    pub fn getRenderSize(self: *SwapchainManager) c.VkExtent2D {
        return self.renderSize;
    }

    pub fn getActiveSwapchains(self: *SwapchainManager) ![]*Swapchain {
        return self.activeSwapchains.items;
    }

    pub fn destroySwapchains(self: *SwapchainManager, hashKeys: []const u32) void {
        const gpi = self.gpi;

        for (hashKeys) |key| {
            const swapchainPtr = self.swapchains.get(key);

            if (swapchainPtr) |swapchain| {
                for (swapchain.views) |view| c.vkDestroyImageView(gpi, view, null);
                for (swapchain.imageRdySemaphores) |sem| c.vkDestroySemaphore(gpi, sem, null);
                for (swapchain.renderDoneSemaphores) |sem| c.vkDestroySemaphore(gpi, sem, null);
                c.vkDestroySwapchainKHR(gpi, swapchain.handle, null);
                c.vkDestroySurfaceKHR(self.instance, swapchain.surface, null);

                self.alloc.free(swapchain.images);
                self.alloc.free(swapchain.views);
                self.alloc.free(swapchain.imageRdySemaphores);
                self.alloc.free(swapchain.renderDoneSemaphores);

                _ = self.swapchains.remove(key);
                std.debug.print("Swapchain Key {} destroyed\n", .{key});
            } else std.debug.print("Cant Swapchain to destroy missing.\n", .{});
        }
    }

    pub fn recreateSwapchain(self: *SwapchainManager, swapchainPtr: *Swapchain, context: *const Context) !void {
        const gpi = self.gpi;

        for (swapchainPtr.views) |view| c.vkDestroyImageView(gpi, view, null);
        for (swapchainPtr.imageRdySemaphores) |sem| c.vkDestroySemaphore(gpi, sem, null);
        for (swapchainPtr.renderDoneSemaphores) |sem| c.vkDestroySemaphore(gpi, sem, null);
        c.vkDestroySwapchainKHR(gpi, swapchainPtr.handle, null);
        //c.vkDestroySurfaceKHR(self.instance, swapchainPtr.surface, null);

        self.alloc.free(swapchainPtr.images);
        self.alloc.free(swapchainPtr.views);
        self.alloc.free(swapchainPtr.imageRdySemaphores);
        self.alloc.free(swapchainPtr.renderDoneSemaphores);

        const alloc = self.alloc;
        const families = context.families;
        const gpu = context.gpu;

        const surface = swapchainPtr.surface;
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

        const actualExtent = pickExtent(&caps, swapchainPtr.extent);

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
            //.oldSwapchain = null,
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

        const newSwapchain = Swapchain{
            .surface = surface,
            .surfaceFormat = surfaceFormat,
            .extent = actualExtent,
            .handle = handle,
            .images = images,
            .views = views,
            .imageRdySemaphores = imageRdySems,
            .renderDoneSemaphores = renderDoneSems,
            .pipeType = swapchainPtr.pipeType,
        };
        swapchainPtr.* = newSwapchain;

        std.debug.print("Swapchain Error Resolved\n", .{});
    }

    pub fn getSwapchainPtr(self: *SwapchainManager, windowId: u32) ?*Swapchain {
        return self.swapchains.getPtr(windowId);
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

fn pickSurfaceFormat(alloc: Allocator, gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkSurfaceFormatKHR {
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
