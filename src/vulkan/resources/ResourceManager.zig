const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const GpuImage = @import("ImageManager.zig").GpuImage;
const ImageManager = @import("ImageManager.zig").ImageManager;
const GpuBuffer = @import("BufferManager.zig").GpuBuffer;
const BufferManager = @import("BufferManager.zig").BufferManager;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const Object = @import("../../ecs/EntityManager.zig").Object;
const rc = @import("../../configs/renderConfig.zig");
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;

pub const ImageMap = CreateMapArray(GpuImage, rc.GPU_IMG_MAX, u32, rc.GPU_IMG_MAX, 0);
pub const BufferMap = CreateMapArray(GpuBuffer, rc.GPU_BUF_MAX, u32, rc.GPU_BUF_MAX, 0);

pub const ResourceManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: GpuAllocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,

    resourceTypes: [rc.GPU_RESOURCE_MAX]enum { Image, Buffer, None } = .{.None} ** rc.GPU_RESOURCE_MAX,
    gpuBuffers: BufferMap = .{},
    gpuImages: ImageMap = .{},

    descMan: DescriptorManager,
    bufferMan: BufferManager,

    pub fn init(alloc: Allocator, context: *const Context) !ResourceManager {
        const gpi = context.gpi;
        const gpu = context.gpu;
        const gpuAlloc = try GpuAllocator.init(context.instance, context.gpi, context.gpu);

        return .{
            .cpuAlloc = alloc,
            .gpuAlloc = gpuAlloc,
            .gpi = gpi,
            .gpu = gpu,
            .bufferMan = BufferManager.init(alloc, gpuAlloc),
            .descMan = try DescriptorManager.init(alloc, gpuAlloc, gpi, gpu),
        };
    }

    pub fn deinit(self: *ResourceManager) void {
        for (self.gpuImages.getElements()) |gpuImg| self.destroyGpuImageDirect(gpuImg);
        self.descMan.deinit();
        self.bufferMan.deinit();
        self.gpuAlloc.deinit();
    }

    pub fn getGpuBuffer(self: *ResourceManager, resourceId: u32) !GpuBuffer {
        return try self.bufferMan.getGpuBuffer(resourceId);
    }

    pub fn getGpuImage(self: *ResourceManager, resourceId: u32) !GpuImage {
        if (self.gpuImages.isKeyUsed(resourceId) == false) return error.GpuImageIdNotUsed;
        return self.gpuImages.get(resourceId);
    }

    pub fn getGpuImagePtr(self: *ResourceManager, resourceId: u32) *GpuImage {
        return self.gpuImages.getPtr(resourceId);
    }

    pub fn getGpuImageMapPtr(self: *ResourceManager) *ImageMap {
        return &self.gpuImages;
    }

    pub fn isGpuImageIdUsed(self: *ResourceManager, resourceId: u32) bool {
        return self.gpuImages.isKeyUsed(resourceId);
    }

    pub fn createGpuImage(self: *ResourceManager, imageSchema: rc.GpuResource.ImageInfo) !void {
        const gpuImg = try self.gpuAlloc.allocGpuImage(imageSchema.extent, imageSchema.imgFormat, imageSchema.memUsage);
        self.gpuImages.set(imageSchema.resourceId, gpuImg);
        try self.descMan.updateImageDescriptor(gpuImg.view, imageSchema.resourceId);
    }

    pub fn createGpuResource(self: *ResourceManager, resourceSchema: rc.GpuResource) !void {
        switch (resourceSchema) {
            .image => |image| {
                try self.createGpuImage(image);
            },
            .buffer => |buffer| {
                try self.createGpuBuffer(buffer);
            },
        }
    }

    pub fn createGpuBuffer(self: *ResourceManager, bindingInf: rc.GpuResource.BufferInf) !void {
        const resourceId = bindingInf.binding;
        try self.bufferMan.createGpuBuffer(bindingInf);
        const gpuBuffer = try self.bufferMan.getGpuBuffer(resourceId);
        try self.descMan.updateBufferDescriptor(gpuBuffer, resourceId, 0);
    }

    pub fn updateGpuImage(self: *ResourceManager, imgInf: rc.GpuResource.ImageInfo) !void {
        self.destroyGpuImage(imgInf.resourceId);
        try self.createGpuImage(imgInf);
    }

    pub fn updateGpuBuffer(self: *ResourceManager, buffInf: rc.GpuResource.BufferInf, data: anytype) !void {
        try self.bufferMan.updateGpuBuffer(buffInf, data);
    }

    // pub fn updateGpuResource(self: *ResourceManager, resourceSchema: rc.ResourceSchema, data: anytype) !void {
    //     switch (resourceSchema) {
    //         .image => |imgInf| {
    //             self.destroyGpuImage(imgInf.resourceId);
    //             try self.createGpuImage(imgInf);
    //         },
    //         .buffer => |bufferInf| {
    //             try self.bufferMan.updateGpuBuffer(bufferInf, data);
    //         },
    //     }
    // }

    pub fn destroyGpuImage(self: *ResourceManager, resourceId: u32) void {
        const gpuImg = self.gpuImages.get(resourceId);
        self.gpuAlloc.freeGpuImage(gpuImg);
    }

    fn destroyGpuImageDirect(self: *ResourceManager, gpuImg: GpuImage) void {
        self.gpuAlloc.freeGpuImage(gpuImg);
    }
};
