const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const GpuImage = @import("ImageManager.zig").GpuImage;
const ImageManager = @import("ImageManager.zig").ImageManager;
const GpuBuffer = @import("BufferManager.zig").GpuBuffer;
const BufferManager = @import("BufferManager.zig").BufferManager;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const ImageMap = @import("ImageManager.zig").ImageMap;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const Object = @import("../../ecs/EntityManager.zig").Object;
const rc = @import("../../configs/renderConfig.zig");

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

    pub fn getGpuBuffer(self: *ResourceManager, resourceId: u32) !GpuBuffer {
        return try self.bufferMan.getGpuBuffer(resourceId);
    }

    pub fn getGpuImage(self: *ResourceManager, resourceId: u32) !GpuImage {
        return try self.imgMan.getGpuImage(resourceId);
    }

    pub fn getGpuImagePtr(self: *ResourceManager, resourceId: u32) *GpuImage {
        return self.imgMan.getGpuImagePtr(resourceId);
    }

    pub fn getGpuImageMapPtr(self: *ResourceManager) *ImageMap {
        return self.imgMan.getGpuImageMapPtr();
    }

    pub fn isGpuImageIdUsed(self: *ResourceManager, resourceId: u32) bool {
        return self.imgMan.isGpuImageIdUsed(resourceId);
    }

    pub fn createGpuImage(self: *ResourceManager, imageSchema: rc.GpuResource.ImageInfo) !void {
        try self.imgMan.createGpuImage(imageSchema);
        const gpuImg = try self.imgMan.getGpuImage(imageSchema.resourceId);
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
        const buffId = bindingInf.binding;
        try self.bufferMan.createGpuBuffer(bindingInf);
        const gpuBuffer = try self.bufferMan.getGpuBuffer(buffId);
        try self.descMan.updateBufferDescriptor(gpuBuffer, buffId, 0);
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
        self.imgMan.destroyGpuImage(resourceId);
    }
};
