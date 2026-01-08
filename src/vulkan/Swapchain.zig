const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const sdl = @import("../modules/sdl.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const Window = @import("../platform/Window.zig").Window;
const vh = @import("Helpers.zig");
const createSemaphore = @import("Scheduler.zig").createSemaphore;
const rc = @import("../configs/renderConfig.zig");
const TextureBase = @import("resources/Texture.zig").TextureBase;
const TexId = @import("resources/Texture.zig").Texture.TexId;

pub const Swapchain = struct {
    surface: vk.VkSurfaceKHR,
    handle: vk.VkSwapchainKHR,
    curIndex: u32 = 0,
    renderTexId: TexId,
    imgRdySems: []vk.VkSemaphore, // indexed by max-in-flight.
    renderDoneSems: []vk.VkSemaphore, // indexed by swapchain images
    textures: []TextureBase, // indexed by swapchain images
    extent: vk.VkExtent2D,
    surfaceFormat: vk.VkSurfaceFormatKHR,
    inUse: bool = true,

    pub fn init(
        alloc: Allocator,
        gpi: vk.VkDevice,
        surfaceFormat: vk.VkSurfaceFormatKHR,
        surface: vk.VkSurfaceKHR,
        extent: vk.VkExtent2D,
        caps: vk.VkSurfaceCapabilitiesKHR,
        renderTexId: TexId,
        oldHandle: ?vk.VkSwapchainKHR,
    ) !Swapchain {
        const mode = rc.DISPLAY_MODE; //try context.pickPresentMode();
        const realExtent = pickExtent(&caps, extent);

        var desiredImgCount: u32 = rc.DESIRED_SWAPCHAIN_IMAGES;
        if (caps.maxImageCount < desiredImgCount) {
            std.debug.print("Swapchain does not support {} Images({}-{}), using {}\n", .{ rc.DESIRED_SWAPCHAIN_IMAGES, caps.minImageCount, caps.maxImageCount, caps.maxImageCount });
            desiredImgCount = caps.maxImageCount;
        } else if (rc.DESIRED_SWAPCHAIN_IMAGES < caps.minImageCount) {
            std.debug.print("Swapchain does not support {} Images ({}-{}), using {}\n", .{ rc.DESIRED_SWAPCHAIN_IMAGES, caps.minImageCount, caps.maxImageCount, caps.minImageCount });
            desiredImgCount = caps.minImageCount;
        }

        const swapchainInf = vk.VkSwapchainCreateInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface,
            .minImageCount = desiredImgCount,
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
        try vh.check(vk.vkCreateSwapchainKHR(gpi, &swapchainInf, null, &handle), "Could not create Swapchain Handle");

        var realImgCount: u32 = 0;
        _ = vk.vkGetSwapchainImagesKHR(gpi, handle, &realImgCount, null);

        const images = try alloc.alloc(vk.VkImage, realImgCount);
        defer alloc.free(images);
        try vh.check(vk.vkGetSwapchainImagesKHR(gpi, handle, &realImgCount, images.ptr), "Could not get Swapchain Images");

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
            try vh.check(vk.vkCreateImageView(gpi, &viewInf, null, &view), "Failed to create image view");

            baseTextures[i] = TextureBase{
                .img = images[i],
                .view = view,
                .format = surfaceFormat.format,
                .texType = .Color,
                .extent = .{ .width = realExtent.width, .height = realExtent.height, .depth = 1 },
                .state = .{ .layout = .Undefined, .stage = .TopOfPipe, .access = .None },
            };
        }

        const renderDoneSems = try alloc.alloc(vk.VkSemaphore, realImgCount);
        errdefer alloc.free(renderDoneSems);
        for (0..realImgCount) |i| renderDoneSems[i] = try createSemaphore(gpi);

        const imgRdySems = try alloc.alloc(vk.VkSemaphore, rc.MAX_IN_FLIGHT);
        errdefer alloc.free(imgRdySems);
        for (0..rc.MAX_IN_FLIGHT) |i| imgRdySems[i] = try createSemaphore(gpi);

        return .{
            .surface = surface,
            .surfaceFormat = surfaceFormat,
            .extent = realExtent,
            .handle = handle,
            .textures = baseTextures,
            .imgRdySems = imgRdySems,
            .renderDoneSems = renderDoneSems,
            .renderTexId = renderTexId,
        };
    }

    pub fn deinit(self: *Swapchain, alloc: Allocator, gpi: vk.VkDevice, instance: vk.VkInstance, deleteMode: enum { withSurface, withoutSurface }) void {
        for (self.textures) |tex| vk.vkDestroyImageView(gpi, tex.view, null);
        for (self.imgRdySems) |sem| vk.vkDestroySemaphore(gpi, sem, null);
        for (self.renderDoneSems) |sem| vk.vkDestroySemaphore(gpi, sem, null);
        vk.vkDestroySwapchainKHR(gpi, self.handle, null);
        if (deleteMode == .withSurface) vk.vkDestroySurfaceKHR(instance, self.surface, null);

        alloc.free(self.textures);
        alloc.free(self.imgRdySems);
        alloc.free(self.renderDoneSems);
    }
};

fn pickExtent(caps: *const vk.VkSurfaceCapabilitiesKHR, curExtent: vk.VkExtent2D) vk.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32)) return caps.currentExtent;
    return vk.VkExtent2D{
        .width = std.math.clamp(curExtent.width, caps.minImageExtent.width, caps.maxImageExtent.width),
        .height = std.math.clamp(curExtent.height, caps.minImageExtent.height, caps.maxImageExtent.height),
    };
}
