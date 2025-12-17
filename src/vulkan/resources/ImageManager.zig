const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const VkAllocator = @import("../vma.zig").VkAllocator;
const check = @import("../error.zig").check;
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;

pub const GpuImage = struct {
    allocation: vk.VmaAllocation,
    img: vk.VkImage,
    view: vk.VkImageView,
    extent3d: vk.VkExtent3D,
    format: vk.VkFormat,
    curLayout: u32 = vk.VK_IMAGE_LAYOUT_UNDEFINED,
};

pub const ImageMap = CreateMapArray(GpuImage, 100, u32, 100, 0);

pub const ImageManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: VkAllocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,

    gpuImages: ImageMap = .{}, // 100 Fixed Images

    pub fn init(cpuAlloc: Allocator, gpuAlloc: VkAllocator, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) ImageManager {
        return .{ .cpuAlloc = cpuAlloc, .gpuAlloc = gpuAlloc, .gpi = gpi, .gpu = gpu };
    }

    pub fn deinit(self: *ImageManager) void {
        for (self.gpuImages.getElements()) |gpuImg| self.destroyGpuImageDirect(gpuImg);
    }

    pub fn createGpuImage(self: *ImageManager, renderId: u8, extent: vk.VkExtent3D, format: vk.VkFormat, usage: vk.VmaMemoryUsage) !void {
        // Extending Flags as Parameters later
        const drawImgUsages = vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            vk.VK_IMAGE_USAGE_STORAGE_BIT |
            vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        // Allocation from GPU local memory
        const imgInf = createAllocatedImageInf(format, drawImgUsages, extent);
        const imgAllocInf = vk.VmaAllocationCreateInfo{ .usage = usage, .requiredFlags = vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT };

        var img: vk.VkImage = undefined;
        var allocation: vk.VmaAllocation = undefined;
        var view: vk.VkImageView = undefined;
        try check(vk.vmaCreateImage(self.gpuAlloc.handle, &imgInf, &imgAllocInf, &img, &allocation, null), "Could not create Render Image");
        const renderViewInf = createAllocatedImageViewInf(format, img, vk.VK_IMAGE_ASPECT_COLOR_BIT);
        try check(vk.vkCreateImageView(self.gpi, &renderViewInf, null, &view), "Could not create Render Image View");

        const gpuImage = GpuImage{ .allocation = allocation, .img = img, .view = view, .extent3d = extent, .format = format };
        self.gpuImages.set(renderId, gpuImage);
    }

    pub fn getImageMapPtr(self: *ImageManager) *ImageMap {
        return &self.gpuImages;
    }

    pub fn gpuImgIdUsed(self: *ImageManager, renderId: u8) bool {
        return self.gpuImages.isKeyUsed(renderId);
    }

    pub fn getGpuImage(self: *ImageManager, renderId: u8) GpuImage {
        return self.gpuImages.get(renderId);
    }

    pub fn getGpuImagePtr(self: *ImageManager, renderId: u8) *GpuImage {
        return self.gpuImages.getPtr(renderId);
    }

    pub fn destroyGpuImage(self: *ImageManager, renderId: u8) void {
        const gpuImg = self.gpuImages.get(renderId);
        vk.vkDestroyImageView(self.gpi, gpuImg.view, null);
        vk.vmaDestroyImage(self.gpuAlloc.handle, gpuImg.img, gpuImg.allocation);
    }

    fn destroyGpuImageDirect(self: *ImageManager, gpuImg: GpuImage) void {
        vk.vkDestroyImageView(self.gpi, gpuImg.view, null);
        vk.vmaDestroyImage(self.gpuAlloc.handle, gpuImg.img, gpuImg.allocation);
    }
};

fn createAllocatedImageInf(format: vk.VkFormat, usageFlags: vk.VkImageUsageFlags, extent3d: vk.VkExtent3D) vk.VkImageCreateInfo {
    return vk.VkImageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent3d,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT, // MSAA not used by default!
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL, // Optimal GPU Format has to be changed to LINEAR for CPU Read
        .usage = usageFlags,
    };
}

fn createAllocatedImageViewInf(format: vk.VkFormat, image: vk.VkImage, aspectFlags: vk.VkImageAspectFlags) vk.VkImageViewCreateInfo {
    return vk.VkImageViewCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .image = image,
        .format = format,
        .subresourceRange = vk.VkImageSubresourceRange{
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .aspectMask = aspectFlags,
        },
    };
}
