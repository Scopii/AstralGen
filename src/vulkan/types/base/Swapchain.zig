const TextureBase = @import("../res/TextureBase.zig").TextureBase;
const TexId = @import("../res/Texture.zig").Texture.TexId;
const rc = @import("../../../configs/renderConfig.zig");
const vk = @import("../../../modules/vk.zig").c;
const vhF = @import("../../help/Functions.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

pub const Swapchain = struct {
    surface: vk.VkSurfaceKHR,
    handle: vk.VkSwapchainKHR,
    curIndex: u32 = 0,
    renderTexId: TexId,
    acquireSems: []vk.VkSemaphore, // indexed by max-in-flight.
    renderSems: []vk.VkSemaphore, // indexed by swapchain images
    textures: []TextureBase, // indexed by swapchain images
    extent: vk.VkExtent2D,
    inUse: bool = true,

    pub fn init(alloc: Allocator, gpi: vk.VkDevice, surface: vk.VkSurfaceKHR, extent: vk.VkExtent2D, gpu: vk.VkPhysicalDevice, renderTexId: TexId, oldHandle: ?vk.VkSwapchainKHR) !Swapchain {
        const mode = rc.DISPLAY_MODE; //try context.pickPresentMode();
        const caps = try getSurfaceCaps(gpu, surface);
        const realExtent = pickExtent(&caps, extent);
        const surfaceFormat = try pickSurfaceFormat(alloc, gpu, surface);

        var desired: u32 = rc.DESIRED_SWAPCHAIN_IMAGES;
        if (caps.maxImageCount < desired) {
            std.debug.print("Swapchain does not support {} Images({}-{}), using {}\n", .{ desired, caps.minImageCount, caps.maxImageCount, caps.maxImageCount });
            desired = caps.maxImageCount;
        } else if (rc.DESIRED_SWAPCHAIN_IMAGES < caps.minImageCount) {
            std.debug.print("Swapchain does not support {} Images ({}-{}), using {}\n", .{ desired, caps.minImageCount, caps.maxImageCount, caps.minImageCount });
            desired = caps.minImageCount;
        }

        const swapchainInf = vk.VkSwapchainCreateInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface,
            .minImageCount = desired,
            .imageFormat = surfaceFormat.format,
            .imageColorSpace = surfaceFormat.colorSpace,
            .imageExtent = realExtent,
            .imageArrayLayers = 1,
            .imageUsage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0, // Not Needed for Exclusive
            .pQueueFamilyIndices = null, // Not Needed for Exclusive
            .preTransform = caps.currentTransform,
            .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = mode,
            .clipped = vk.VK_TRUE,
            .oldSwapchain = if (oldHandle != null) oldHandle.? else null,
        };
        var handle: vk.VkSwapchainKHR = undefined;
        try vhF.check(vk.vkCreateSwapchainKHR(gpi, &swapchainInf, null, &handle), "Could not create Swapchain Handle");

        var realImgCount: u32 = 0;
        _ = vk.vkGetSwapchainImagesKHR(gpi, handle, &realImgCount, null);

        const images = try alloc.alloc(vk.VkImage, realImgCount);
        defer alloc.free(images);
        try vhF.check(vk.vkGetSwapchainImagesKHR(gpi, handle, &realImgCount, images.ptr), "Could not get Swapchain Images");

        const baseTextures = try alloc.alloc(TextureBase, realImgCount);
        errdefer alloc.free(baseTextures);

        for (0..realImgCount) |i| {
            const viewInf = vk.VkImageViewCreateInfo{
                .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = images[i],
                .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
                .format = surfaceFormat.format,
                .subresourceRange = vk.VkImageSubresourceRange{
                    .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            var view: vk.VkImageView = undefined;
            try vhF.check(vk.vkCreateImageView(gpi, &viewInf, null, &view), "Failed to create image view");

            baseTextures[i] = TextureBase{
                .img = images[i],
                .view = view,
                .texType = .Color,
                .extent = .{ .width = realExtent.width, .height = realExtent.height, .depth = 1 },
                .state = .{ .layout = .Undefined, .stage = .ColorAtt, .access = .None },
                .viewInf = viewInf,
            };
        }

        const renderDoneSems = try alloc.alloc(vk.VkSemaphore, realImgCount);
        errdefer alloc.free(renderDoneSems);
        for (0..realImgCount) |i| renderDoneSems[i] = try vhF.createSemaphore(gpi);

        const imgRdySems = try alloc.alloc(vk.VkSemaphore, rc.MAX_IN_FLIGHT);
        errdefer alloc.free(imgRdySems);
        for (0..rc.MAX_IN_FLIGHT) |i| imgRdySems[i] = try vhF.createSemaphore(gpi);

        return .{
            .surface = surface,
            .extent = realExtent,
            .handle = handle,
            .textures = baseTextures,
            .acquireSems = imgRdySems,
            .renderSems = renderDoneSems,
            .renderTexId = renderTexId,
        };
    }

    pub fn deinit(self: *Swapchain, alloc: Allocator, gpi: vk.VkDevice, instance: vk.VkInstance, deleteMode: enum { withSurface, withoutSurface }) void {
        for (self.textures) |tex| vk.vkDestroyImageView(gpi, tex.view, null);
        for (self.acquireSems) |sem| vk.vkDestroySemaphore(gpi, sem, null);
        for (self.renderSems) |sem| vk.vkDestroySemaphore(gpi, sem, null);
        vk.vkDestroySwapchainKHR(gpi, self.handle, null);
        if (deleteMode == .withSurface) vk.vkDestroySurfaceKHR(instance, self.surface, null);

        alloc.free(self.textures);
        alloc.free(self.acquireSems);
        alloc.free(self.renderSems);
    }

    pub fn recreate(self: *Swapchain, alloc: Allocator, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice, instance: vk.VkInstance, newExtent: vk.VkExtent2D) !void {
        const swapchain = try Swapchain.init(alloc, gpi, self.surface, newExtent, gpu, self.renderTexId, self.handle);
        self.deinit(alloc, gpi, instance, .withoutSurface);
        self.* = swapchain;
    }

    pub fn acquireNextImage(self: *Swapchain, gpi: vk.VkDevice, flightId: u8) vk.VkResult {
        return vk.vkAcquireNextImageKHR(gpi, self.handle, std.math.maxInt(u64), self.acquireSems[flightId], null, &self.curIndex);
    }

    pub fn getCurTexture(self: *Swapchain) *TextureBase {
        return &self.textures[self.curIndex];
    }

    pub fn getExtent2D(self: *Swapchain) vk.VkExtent2D {
        return vk.VkExtent2D{ .height = self.extent.height, .width = self.extent.width };
    }

    pub fn getExtent3D(self: *Swapchain) vk.VkExtent3D {
        return vk.VkExtent3D{ .height = self.extent.height, .width = self.extent.width, .depth = 1 };
    }
};

fn pickExtent(caps: *const vk.VkSurfaceCapabilitiesKHR, curExtent: vk.VkExtent2D) vk.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32)) return caps.currentExtent;
    return vk.VkExtent2D{
        .width = std.math.clamp(curExtent.width, caps.minImageExtent.width, caps.maxImageExtent.width),
        .height = std.math.clamp(curExtent.height, caps.minImageExtent.height, caps.maxImageExtent.height),
    };
}

fn getSurfaceCaps(gpu: vk.VkPhysicalDevice, surface: vk.VkSurfaceKHR) !vk.VkSurfaceCapabilitiesKHR {
    var caps: vk.VkSurfaceCapabilitiesKHR = undefined;
    try vhF.check(vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &caps), "Failed to get surface capabilities");
    return caps;
}

fn pickSurfaceFormat(alloc: Allocator, gpu: vk.VkPhysicalDevice, surface: vk.VkSurfaceKHR) !vk.VkSurfaceFormatKHR {
    var formatCount: u32 = 0;
    try vhF.check(vk.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, null), "Failed to get format count");
    if (formatCount == 0) return error.NoSurfaceFormats;

    const formats = try alloc.alloc(vk.VkSurfaceFormatKHR, formatCount);
    defer alloc.free(formats);

    try vhF.check(vk.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, formats.ptr), "Failed to get surface formats");
    // Return preferred format if available otherwise first one
    if (formats.len == 1 and formats[0].format == vk.VK_FORMAT_UNDEFINED) {
        return vk.VkSurfaceFormatKHR{ .format = vk.VK_FORMAT_B8G8R8A8_UNORM, .colorSpace = vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR };
    }

    for (formats) |format| {
        if (format.format == vk.VK_FORMAT_B8G8R8A8_UNORM and format.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) return format;
    }
    return formats[0];
}
