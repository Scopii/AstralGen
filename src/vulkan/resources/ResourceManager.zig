const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const GpuImage = @import("ImageManager.zig").GpuImage;
const ImageManager = @import("ImageManager.zig").ImageManager;
const GpuBuffer = @import("BufferManager.zig").GpuBuffer;
const BufferManager = @import("BufferManager.zig").BufferManager;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const ImageMap = @import("ImageManager.zig").ImageMap;
const VkAllocator = @import("../vma.zig").VkAllocator;
const check = @import("../error.zig").check;
const config = @import("../../config.zig");
const Object = @import("../../ecs/EntityManager.zig").Object;
const RENDER_IMG_MAX = config.RENDER_IMG_MAX;

pub const ResourceManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: VkAllocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,

    imgMan: ImageManager,
    bufferMan: BufferManager,
    descMan: DescriptorManager,

    pub fn init(alloc: Allocator, context: *const Context) !ResourceManager {
        const gpi = context.gpi;
        const gpu = context.gpu;
        const gpuAlloc = try VkAllocator.init(context.instance, context.gpi, context.gpu);

        return .{
            .cpuAlloc = alloc,
            .gpuAlloc = gpuAlloc,
            .gpi = gpi,
            .gpu = gpu,
            .imgMan = ImageManager.init(alloc, gpuAlloc, gpi, gpu),
            .bufferMan = BufferManager.init(alloc, gpuAlloc, gpi, gpu),
            .descMan = try DescriptorManager.init(alloc, gpuAlloc, gpi, gpu),
        };
    }

    pub fn deinit(self: *ResourceManager) void {
        self.imgMan.deinit();
        self.descMan.deinit();
        self.bufferMan.deinit();
        self.gpuAlloc.deinit();
    }

    pub fn getGpuBuffer(self: *ResourceManager, buffId: u8) !GpuBuffer {
        return try self.bufferMan.getGpuBuffer(buffId);
    }

    pub fn getRenderImg(self: *ResourceManager, renderId: u8) GpuImage {
        return self.imgMan.getGpuImage(renderId);
    }

    pub fn getRenderImgPtr(self: *ResourceManager, renderId: u8) *GpuImage {
        return self.imgMan.getGpuImagePtr(renderId);
    }

    pub fn gpuImgIdUsed(self: *ResourceManager, renderId: u8) bool {
        return self.imgMan.gpuImgIdUsed(renderId);
    }

    pub fn createGpuImage(self: *ResourceManager, renderId: u8, extent: vk.VkExtent3D, format: vk.VkFormat, usage: vk.VmaMemoryUsage) !void {
        try self.imgMan.createGpuImage(renderId, extent, format, usage);
    }

    pub fn getImageMapPtr(self: *ResourceManager) *ImageMap {
        return self.imgMan.getImageMapPtr();
    }

    pub fn updateImageDescriptor(self: *ResourceManager, renderId: u8) !void {
        const imgView = self.imgMan.getGpuImage(renderId).view;
        try self.descMan.updateImageDescriptor(imgView, renderId);
    }

    pub fn createGpuBuffer(self: *ResourceManager, buffId: u8, objects: []Object) !void {
        try self.bufferMan.createGpuBuffer(buffId, objects);
    }

    pub fn updateObjectBufferDescriptor(self: *ResourceManager, buffId: u8) !void {
        const gpuBuffer = try self.bufferMan.getGpuBuffer(buffId);
        try self.descMan.updateObjectBufferDescriptor(gpuBuffer);
    }

    pub fn destroyGpuImage(self: *ResourceManager, renderId: u8) void {
        self.imgMan.destroyGpuImage(renderId);
    }
};
