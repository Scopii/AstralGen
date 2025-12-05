const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const Window = @import("../platform/Window.zig").Window;
const QueueFamilies = @import("Context.zig").QueueFamilies;
const RenderPass = @import("../config.zig").RenderPass;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const check = @import("error.zig").check;
const createSemaphore = @import("primitives.zig").createSemaphore;

const config = @import("../config.zig");
const MAX_IN_FLIGHT = config.MAX_IN_FLIGHT;
const MAX_WINDOWS = config.MAX_WINDOWS;
const DESIRED_SWAPCHAIN_IMAGES = config.DESIRED_SWAPCHAIN_IMAGES;
const DISPLAY_MODE = config.DISPLAY_MODE;

pub const Swapchain = struct {
    surface: c.VkSurfaceKHR,
    handle: c.VkSwapchainKHR,
    extent: c.VkExtent2D,
    images: []c.VkImage,
    views: []c.VkImageView,
    curIndex: u32 = 0,
    imgRdySems: []c.VkSemaphore, // indexed by max-in-flight.
    renderDoneSems: []c.VkSemaphore, // indexed by swapchain images
    surfaceFormat: c.VkSurfaceFormatKHR,
};

pub const SwapchainManager = struct {
    const renderPasses = @typeInfo(RenderPass).@"enum".fields.len;

    alloc: Allocator,
    gpi: c.VkDevice,
    instance: c.VkInstance,
    maxExtent: c.VkExtent2D = .{ .width = 0, .height = 0 },
    swapchains: CreateMapArray(Swapchain, MAX_WINDOWS, u8, MAX_WINDOWS, 0) = .{},
    activeGroups: [renderPasses]std.BoundedArray(u8, MAX_WINDOWS),
    targets: std.BoundedArray(u8, MAX_WINDOWS) = .{},

    pub fn init(alloc: Allocator, context: *const Context) !SwapchainManager {
        var activeGroups: [renderPasses]std.BoundedArray(u8, MAX_WINDOWS) = undefined;
        for (0..renderPasses) |i| activeGroups[i] = .{};

        return .{
            .alloc = alloc,
            .gpi = context.gpi,
            .instance = context.instance,
            .activeGroups = activeGroups,
        };
    }

    pub fn deinit(self: *SwapchainManager) void {
        for (self.swapchains.getElements()) |*swapchain| {
            self.destroySwapchain(swapchain, .withSurface);
        }
    }

    pub fn updateTargets(self: *SwapchainManager, frameInFlight: u8, context: *Context) !bool {
        self.targets.clear();
        const activeGroups = self.activeGroups;
        const gpi = self.gpi;

        for (0..activeGroups.len) |i| {
            for (activeGroups[i].slice()) |id| {
                const index = self.swapchains.getIndex(id);
                const ptr = self.swapchains.getPtrAtIndex(index);
                const result1 = c.vkAcquireNextImageKHR(gpi, ptr.handle, std.math.maxInt(u64), ptr.imgRdySems[frameInFlight], null, &ptr.curIndex);

                switch (result1) {
                    c.VK_SUCCESS => try self.targets.append(index),
                    c.VK_ERROR_OUT_OF_DATE_KHR, c.VK_SUBOPTIMAL_KHR => {
                        try self.createSwapchain(context, .{ .id = id });
                        const result2 = c.vkAcquireNextImageKHR(gpi, ptr.handle, std.math.maxInt(u64), ptr.imgRdySems[frameInFlight], null, &ptr.curIndex);

                        if (result2 == c.VK_SUCCESS) {
                            try self.targets.append(index);
                            std.debug.print("Resolved Error for Swapchain {}", .{ptr.*});
                        } else std.debug.print("Could not Resolve Swapchain Error {}", .{ptr.*});
                    },
                    else => try check(result1, "Could not acquire swapchain image"),
                }
            }
        }
        return if (self.targets.len != 0) true else false;
    }

    pub fn addActive(self: *SwapchainManager, window: *Window) !void {
        try self.activeGroups[@intFromEnum(window.renderPass)].append(@intCast(window.id));
    }

    pub fn removeActive(self: *SwapchainManager, window: *Window) void {
        const group = self.activeGroups[@intFromEnum(window.renderPass)].slice();
        for (0..group.len) |i| {
            if (group[i] == window.id)
                _ = self.activeGroups[@intFromEnum(window.renderPass)].swapRemove(i);
        }
    }

    pub fn updateMaxExtent(self: *SwapchainManager) void {
        var maxWidth: u32 = 0;
        var maxHeight: u32 = 0;

        for (0..self.activeGroups.len) |i| {
            const slice = self.activeGroups[i].slice();

            for (0..slice.len) |index| {
                const ptr = self.swapchains.getPtr(slice[index]);
                maxWidth = @max(maxWidth, ptr.extent.width);
                maxHeight = @max(maxHeight, ptr.extent.height);
            }
        }
        self.maxExtent = c.VkExtent2D{ .width = maxWidth, .height = maxHeight };
    }

    pub fn getMaxExtent(self: *SwapchainManager) c.VkExtent2D {
        return self.maxExtent;
    }

    pub fn removeSwapchain(self: *SwapchainManager, windows: []const *Window) void {
        for (windows) |window| {
            const key = window.id;

            if (self.swapchains.isKeyValid(@intCast(key)) == true) {
                self.destroySwapchain(self.swapchains.getPtr(@intCast(key)), .withSurface);

                _ = self.swapchains.removeAtKey(@intCast(key));
                self.removeActive(window);

                std.debug.print("Swapchain Key {} destroyed\n", .{key});
            } else std.debug.print("Cant Swapchain to destroy missing.\n", .{});
        }
    }

    fn destroySwapchain(self: *SwapchainManager, sc: *Swapchain, deleteMode: enum { withSurface, withoutSurface }) void {
        const gpi = self.gpi;

        for (sc.views) |view| c.vkDestroyImageView(gpi, view, null);
        for (sc.imgRdySems) |sem| c.vkDestroySemaphore(gpi, sem, null);
        for (sc.renderDoneSems) |sem| c.vkDestroySemaphore(gpi, sem, null);
        c.vkDestroySwapchainKHR(gpi, sc.handle, null);
        if (deleteMode == .withSurface) c.vkDestroySurfaceKHR(self.instance, sc.surface, null);

        self.alloc.free(sc.images);
        self.alloc.free(sc.views);
        self.alloc.free(sc.imgRdySems);
        self.alloc.free(sc.renderDoneSems);
    }

    pub fn createSwapchain(self: *SwapchainManager, context: *const Context, input: union(enum) { window: *Window, id: u8 }) !void {
        const alloc = self.alloc;
        const gpu = context.gpu;
        var extent: c.VkExtent2D = undefined;
        var ptr: *Swapchain = undefined;

        switch (input) {
            .window => |w| if (w.status == .needCreation) {
                extent = w.extent;
                const surface = try createSurface(w.handle, self.instance);
                const caps = try getSurfaceCaps(gpu, surface);
                const surfaceFormat = try pickSurfaceFormat(alloc, gpu, surface);

                const swapchain = try self.createInternalSwapchain(surfaceFormat, surface, extent, caps, null);
                self.swapchains.set(@intCast(w.id), swapchain);
                try self.activeGroups[@intFromEnum(w.renderPass)].append(@intCast(w.id));
                std.debug.print("Swapchain added to Window {}\n", .{w.id});
                return;
            } else {
                ptr = self.swapchains.getPtr(@intCast(w.id));
                extent = w.extent;
                std.debug.print("Swapchain recreated\n", .{});
            },
            .id => |id| {
                ptr = self.swapchains.getPtr(@intCast(id));
                extent = ptr.extent;
                std.debug.print("Swapchain Error resolved\n", .{});
            },
        }

        const surface = ptr.surface;
        const caps = try getSurfaceCaps(gpu, surface);
        const surfaceFormat = try pickSurfaceFormat(alloc, gpu, surface);

        const swapchain = try self.createInternalSwapchain(surfaceFormat, surface, extent, caps, ptr.handle);
        self.destroySwapchain(ptr, .withoutSurface);
        ptr.* = swapchain;
    }

    fn createInternalSwapchain(
        self: *SwapchainManager,
        surfaceFormat: c.VkSurfaceFormatKHR,
        surface: c.VkSurfaceKHR,
        extent: c.VkExtent2D,
        caps: c.VkSurfaceCapabilitiesKHR,
        oldHandle: ?c.VkSwapchainKHR,
    ) !Swapchain {
        const alloc = self.alloc;
        const gpi = self.gpi;
        const mode = DISPLAY_MODE; //try context.pickPresentMode();
        const actualExtent = pickExtent(&caps, extent);

        var desiredImgCount: u32 = DESIRED_SWAPCHAIN_IMAGES;
        if (caps.maxImageCount < desiredImgCount) {
            std.debug.print("Swapchain does not support {} Images({}-{}), using {}\n", .{ DESIRED_SWAPCHAIN_IMAGES, caps.minImageCount, caps.maxImageCount, caps.maxImageCount });
            desiredImgCount = caps.maxImageCount;
        } else if (DESIRED_SWAPCHAIN_IMAGES < caps.minImageCount) {
            std.debug.print("Swapchain does not support {} Images ({}-{}), using {}\n", .{ DESIRED_SWAPCHAIN_IMAGES, caps.minImageCount, caps.maxImageCount, caps.minImageCount });
            desiredImgCount = caps.minImageCount;
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
            .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0, // Not Needed for Exclusive
            .pQueueFamilyIndices = null, // Not Needed for Exclusive
            .preTransform = caps.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = mode,
            .clipped = c.VK_TRUE,
            .oldSwapchain = if (oldHandle != null) oldHandle.? else null,
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

        return .{
            .surface = surface,
            .surfaceFormat = surfaceFormat,
            .extent = actualExtent,
            .handle = handle,
            .images = images,
            .views = views,
            .imgRdySems = imageRdySems,
            .renderDoneSems = renderDoneSems,
        };
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
