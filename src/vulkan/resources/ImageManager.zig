const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
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

pub const ImageMap = CreateMapArray(GpuImage, 100, u32, 100, 0); // 100 Fixed Images

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

    pub fn createGpuImage(self: *ImageManager, renderId: u8, extent: vk.VkExtent3D, format: vk.VkFormat, usage: vk.VmaMemoryUsage) !void {
        const gpuImage = try self.gpuAlloc.allocGpuImage(extent, format, usage);
        self.gpuImages.set(renderId, gpuImage);
    }

    pub fn getGpuImageMapPtr(self: *ImageManager) *ImageMap {
        return &self.gpuImages;
    }

    pub fn isGpuImageIdUsed(self: *ImageManager, renderId: u8) bool {
        return self.gpuImages.isKeyUsed(renderId);
    }

    pub fn getGpuImage(self: *ImageManager, renderId: u8) !GpuImage {
        if (self.gpuImages.isKeyUsed(renderId) == false) return error.GpuImageIdNotUsed;
        return self.gpuImages.get(renderId);
    }

    pub fn getGpuImagePtr(self: *ImageManager, renderId: u8) *GpuImage {
        return self.gpuImages.getPtr(renderId);
    }

    pub fn destroyGpuImage(self: *ImageManager, renderId: u8) void {
        const gpuImg = self.gpuImages.get(renderId);
        self.gpuAlloc.freeGpuImage(gpuImg);
    }

    fn destroyGpuImageDirect(self: *ImageManager, gpuImg: GpuImage) void {
        self.gpuAlloc.freeGpuImage(gpuImg);
    }
};
