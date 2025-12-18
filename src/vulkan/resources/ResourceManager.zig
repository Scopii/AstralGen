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
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const check = @import("../error.zig").check;
const config = @import("../../config.zig");
const Object = @import("../../ecs/EntityManager.zig").Object;
const RENDER_IMG_MAX = config.RENDER_IMG_MAX;

pub const ResourceManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: GpuAllocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,

    imgMan: ImageManager,
    bufferMan: BufferManager,
    descMan: DescriptorManager,

    pub fn init(alloc: Allocator, context: *const Context) !ResourceManager {
        const gpi = context.gpi;
        const gpu = context.gpu;
        const gpuAlloc = try GpuAllocator.init(context.instance, context.gpi, context.gpu);

        return .{
            .cpuAlloc = alloc,
            .gpuAlloc = gpuAlloc,
            .gpi = gpi,
            .gpu = gpu,
            .imgMan = ImageManager.init(alloc, gpuAlloc),
            .bufferMan = BufferManager.init(alloc, gpuAlloc),
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

    pub fn getGpuImage(self: *ResourceManager, renderId: u8) !GpuImage {
        return try self.imgMan.getGpuImage(renderId);
    }

    pub fn getGpuImagePtr(self: *ResourceManager, renderId: u8) *GpuImage {
        return self.imgMan.getGpuImagePtr(renderId);
    }

    pub fn getGpuImageMapPtr(self: *ResourceManager) *ImageMap {
        return self.imgMan.getGpuImageMapPtr();
    }

    pub fn isGpuImageIdUsed(self: *ResourceManager, renderId: u8) bool {
        return self.imgMan.isGpuImageIdUsed(renderId);
    }

    pub fn createGpuImage(self: *ResourceManager, renderId: u8, extent: vk.VkExtent3D, format: vk.VkFormat, usage: vk.VmaMemoryUsage) !void {
        try self.imgMan.createGpuImage(renderId, extent, format, usage);
        const gpuImg = try self.imgMan.getGpuImage(renderId);
        try self.descMan.updateImageDescriptor(gpuImg.view, renderId);
    }

    pub fn createGpuBuffer(self: *ResourceManager, buffId: u8, objects: []Object) !void {
        try self.bufferMan.createGpuBuffer(buffId, objects);
        const gpuBuffer = try self.bufferMan.getGpuBuffer(buffId);
        try self.descMan.updateBufferDescriptor(gpuBuffer, buffId);
    }

    pub fn destroyGpuImage(self: *ResourceManager, renderId: u8) void {
        self.imgMan.destroyGpuImage(renderId);
    }
};
