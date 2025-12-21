const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const rc = @import("../../configs/renderConfig.zig");
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;

pub const GpuImage = struct {
    allocation: vk.VmaAllocation,
    img: vk.VkImage,
    view: vk.VkImageView,
    extent3d: vk.VkExtent3D,
    format: vk.VkFormat,
    curLayout: u32 = vk.VK_IMAGE_LAYOUT_UNDEFINED,
};

pub const ImageMap = CreateMapArray(GpuImage, rc.GPU_IMG_MAX, u32, rc.GPU_IMG_MAX, 0);

pub const ImageManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: GpuAllocator, //deinit() in ResourceManager

    gpuImages: ImageMap = .{},

    pub fn init(cpuAlloc: Allocator, gpuAlloc: GpuAllocator) ImageManager {
        return .{ .cpuAlloc = cpuAlloc, .gpuAlloc = gpuAlloc };
    }

    pub fn deinit(self: *ImageManager) void {
        for (self.gpuImages.getElements()) |gpuImg| self.destroyGpuImageDirect(gpuImg);
    }

    pub fn createGpuImage(self: *ImageManager, imageSchema: rc.ResourceSchema.ImageResource) !void {
        const gpuImage = try self.gpuAlloc.allocGpuImage(imageSchema.extent, imageSchema.imgFormat, imageSchema.memUsage);
        self.gpuImages.set(imageSchema.resourceId, gpuImage);
    }

    pub fn getGpuImageMapPtr(self: *ImageManager) *ImageMap {
        return &self.gpuImages;
    }

    pub fn isGpuImageIdUsed(self: *ImageManager, imgId: u32) bool {
        return self.gpuImages.isKeyUsed(imgId);
    }

    pub fn getGpuImage(self: *ImageManager, imgId: u32) !GpuImage {
        if (self.gpuImages.isKeyUsed(imgId) == false) return error.GpuImageIdNotUsed;
        return self.gpuImages.get(imgId);
    }

    pub fn getGpuImagePtr(self: *ImageManager, imgId: u32) *GpuImage {
        return self.gpuImages.getPtr(imgId);
    }

    pub fn destroyGpuImage(self: *ImageManager, imgId: u32) void {
        const gpuImg = self.gpuImages.get(imgId);
        self.gpuAlloc.freeGpuImage(gpuImg);
    }

    fn destroyGpuImageDirect(self: *ImageManager, gpuImg: GpuImage) void {
        self.gpuAlloc.freeGpuImage(gpuImg);
    }
};
