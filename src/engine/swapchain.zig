const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;
const Device = @import("device.zig").Device;
const ImageBucket = @import("image.zig").ImageBucket;

// Import QueueFamilies from device.zig
const QueueFamilies = @import("device.zig").QueueFamilies;

pub const Swapchain = struct {
    alloc: Allocator,
    handle: c.VkSwapchainKHR,
    surfaceFormat: c.VkSurfaceFormatKHR,
    mode: c.VkPresentModeKHR,
    extent: c.VkExtent2D,
    imageCount: u32 = undefined,
    imageBucket: ImageBucket = undefined,

    pub fn init(alloc: Allocator, device: *const Device, surface: c.VkSurfaceKHR, currExtent: *const c.VkExtent2D) !Swapchain {
        const gpi = device.gpi;
        const gpu = device.gpu;
        const families = device.families;

        var details = try checkSwapchainSupport(alloc, gpu, surface); // Get swapchain support details
        defer details.deinit(); // Clean up details after use

        const surfaceFormat = try pickSurfaceFormat(details);
        const mode = pickPresentMode(details);
        const extent = pickExtent(details.caps, currExtent);

        // Create swapchain
        var desiredImageCount = details.caps.minImageCount + 1;
        if (details.caps.maxImageCount > 0 and desiredImageCount > details.caps.maxImageCount) {
            desiredImageCount = details.caps.maxImageCount; // Clamp to max if exists
        }

        var sharingMode: c.VkSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        var familyIndices: [2]u32 = undefined;
        var familyCount: u32 = 0;

        if (families.graphics != families.present) {
            sharingMode = c.VK_SHARING_MODE_CONCURRENT; // Need concurrent access
            familyIndices[0] = families.graphics;
            familyIndices[1] = families.present;
            familyCount = 2;
        }

        const swapchainInfo = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface,
            .minImageCount = desiredImageCount,
            .imageFormat = surfaceFormat.format,
            .imageColorSpace = surfaceFormat.colorSpace,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = sharingMode,
            .queueFamilyIndexCount = familyCount,
            .pQueueFamilyIndices = if (familyCount > 0) &familyIndices else null,
            .preTransform = details.caps.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = mode, // Doesnt work?
            .clipped = c.VK_TRUE,
        };

        var handle: c.VkSwapchainKHR = undefined;
        try check(c.vkCreateSwapchainKHR(gpi, &swapchainInfo, null, &handle), "Could not Create Swapchain");

        var actualImageCount: u32 = 0;
        try check(c.vkGetSwapchainImagesKHR(gpi, handle, &actualImageCount, null), "Could not get Swapchain Images");

        const imageBucket = try ImageBucket.init(alloc, actualImageCount, gpi, handle, surfaceFormat.format);

        return .{
            .alloc = alloc,
            .handle = handle,
            .surfaceFormat = surfaceFormat,
            .mode = mode,
            .extent = extent,
            .imageCount = actualImageCount,
            .imageBucket = imageBucket,
        };
    }

    pub fn deinit(self: *Swapchain, gpi: c.VkDevice) void {
        self.imageBucket.deinit(self.alloc, gpi);
        c.vkDestroySwapchainKHR(gpi, self.handle, null);
    }
};

pub const SwapchainDetails = struct {
    arena: std.heap.ArenaAllocator,
    caps: c.VkSurfaceCapabilitiesKHR = undefined,
    formats: []c.VkSurfaceFormatKHR = undefined,
    modes: []c.VkPresentModeKHR = undefined,

    pub fn init(alloc: Allocator) SwapchainDetails {
        return SwapchainDetails{ .arena = std.heap.ArenaAllocator.init(alloc) };
    }

    pub fn deinit(self: *SwapchainDetails) void {
        self.arena.deinit();
    }

    pub fn resizeFormats(self: *SwapchainDetails, count: u32) !void {
        self.formats = try self.arena.allocator().alloc(c.VkSurfaceFormatKHR, count);
    }

    pub fn resizePresentModes(self: *SwapchainDetails, count: u32) !void {
        self.modes = try self.arena.allocator().alloc(c.VkPresentModeKHR, count);
    }
};

pub fn checkSwapchainSupport(alloc: Allocator, gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !SwapchainDetails {
    var details = SwapchainDetails.init(alloc);
    errdefer details.deinit();

    try check(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &details.caps), "Swapchain Support Test failed");

    var formatCount: u32 = 0;
    try check(c.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, null), "Swapchain Support no Format");
    if (formatCount != 0) {
        try details.resizeFormats(formatCount);
        try check(c.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, details.formats.ptr), "Swapchain Support no Format");
    }

    var modeCount: u32 = 0;
    try check(c.vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &modeCount, null), "Swapchain Support no Modes");

    if (modeCount != 0) {
        try details.resizePresentModes(modeCount); // Add try keyword
        try check(c.vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &modeCount, details.modes.ptr), "Swapchain Support no Modes");
    }

    return details;
}

fn pickSurfaceFormat(details: SwapchainDetails) !c.VkSurfaceFormatKHR {
    if (details.formats.len == 1 and details.formats[0].format == c.VK_FORMAT_UNDEFINED) {
        return c.VkSurfaceFormatKHR{
            .format = c.VK_FORMAT_B8G8R8A8_UNORM, //c.VK_FORMAT_B8G8R8A8_SRGB for gamma correction
            .colorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
        };
    }

    for (details.formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_UNORM and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return format;
        }
    }

    return details.formats[0];
}

fn pickPresentMode(details: SwapchainDetails) c.VkPresentModeKHR {
    var best: c.VkPresentModeKHR = c.VK_PRESENT_MODE_FIFO_KHR;
    //VK_PRESENT_MODE_IMMEDIATE_KHR     direct
    //VK_PRESENT_MODE_FIFO_KHR          v-sync?
    //VK_PRESENT_MODE_FIFO_RELAXED_KHR  v-sync light?
    //VK_PRESENT_MODE_MAILBOX_KHR       triple buffering (less latency)

    for (details.modes) |mode| {
        if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return mode;
        } else if (mode == c.VK_PRESENT_MODE_IMMEDIATE_KHR) {
            best = mode;
        }
    }
    return best;
}

fn pickExtent(caps: c.VkSurfaceCapabilitiesKHR, currExtent: *const c.VkExtent2D) c.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32)) return caps.currentExtent;

    const actualExtent = c.VkExtent2D{
        .width = std.math.clamp(currExtent.width, caps.minImageExtent.width, caps.maxImageExtent.width),
        .height = std.math.clamp(currExtent.height, caps.minImageExtent.height, caps.maxImageExtent.height),
    };
    return actualExtent;
}
