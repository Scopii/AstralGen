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

    pub fn init(alloc: Allocator, context: *const Context) !ResourceManager {
        const gpi = context.gpi;
        const gpu = context.gpu;
        const gpuAlloc = try GpuAllocator.init(context.instance, context.gpi, context.gpu);

        return .{
            .cpuAlloc = alloc,
            .gpuAlloc = gpuAlloc,
            .gpi = gpi,
            .gpu = gpu,
            .descMan = try DescriptorManager.init(alloc, gpuAlloc, gpi, gpu),
        };
    }

    pub fn deinit(self: *ResourceManager) void {
        while (self.gpuImages.getCount() > 0) {
            const key = self.gpuImages.getKeyFromIndex(0);
            self.destroyGpuImage(key);
        }
        while (self.gpuBuffers.getCount() > 0) {
            const key = self.gpuBuffers.getKeyFromIndex(0);
            self.destroyGpuBuffer(key);
        }
        self.descMan.deinit();
        self.gpuAlloc.deinit();
    }

    pub fn getGpuBuffer(self: *ResourceManager, resourceId: u32) !GpuBuffer {
        if (self.gpuBuffers.isKeyUsed(resourceId) == false) return error.GpuBufferDoesNotExist;
        return self.gpuBuffers.get(resourceId);
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

    pub fn createGpuImage(self: *ResourceManager, image: rc.GpuResource.ImageInfo) !void {
        const gpuImg = try self.gpuAlloc.allocGpuImage(image.extent, image.imgFormat, image.memUsage);
        self.gpuImages.set(image.resourceId, gpuImg);
        try self.descMan.updateImageDescriptor(gpuImg.view, image.resourceId);
        self.resourceTypes[image.resourceId] = .Image;
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
        const buffer = try self.gpuAlloc.allocDefinedBuffer(bindingInf);
        self.gpuBuffers.set(bindingInf.binding, buffer);
        try self.descMan.updateBufferDescriptor(buffer, resourceId, 0);
        self.resourceTypes[resourceId] = .Buffer;
    }

    pub fn updateGpuImage(self: *ResourceManager, imgInf: rc.GpuResource.ImageInfo) !void {
        self.destroyGpuImage(imgInf.resourceId);
        try self.createGpuImage(imgInf);
    }

    pub fn updateGpuBuffer(self: *ResourceManager, buffInf: rc.GpuResource.BufferInf, data: anytype) !void {
        const T = std.meta.Child(@TypeOf(data));
        if (@sizeOf(T) != buffInf.elementSize) {
            std.debug.print("Error: Size mismatch! Config expects {} bytes, Data is {} bytes\n", .{ buffInf.elementSize, @sizeOf(T) });
            return error.TypeMismatch;
        }
        const buffId = buffInf.binding;
        var buffer = try self.getGpuBuffer(buffId);
        const pMappedData = buffer.allocInf.pMappedData;
        // Simple alignment check
        const alignment = @alignOf(T);
        if (@intFromPtr(pMappedData) % alignment != 0) {
            return error.ImproperAlignment;
        }
        // Copy
        const dataPtr: [*]T = @ptrCast(@alignCast(pMappedData));
        @memcpy(dataPtr[0..data.len], data);
        // Update
        buffer.count = @intCast(data.len);
        self.gpuBuffers.set(buffId, buffer);
    }

    pub fn destroyGpuImage(self: *ResourceManager, resourceId: u32) void {
        if (self.gpuImages.isKeyUsed(resourceId) == true) {
            const gpuImg = self.gpuImages.get(resourceId);
            self.gpuAlloc.freeGpuImage(gpuImg);
            self.gpuImages.removeAtKey(resourceId);
            self.resourceTypes[resourceId] = .None;
        }
    }

    pub fn destroyGpuBuffer(self: *ResourceManager, resourceId: u32) void {
        if (self.gpuBuffers.isKeyUsed(resourceId)) {
            const gpuBuffer = self.gpuBuffers.get(resourceId);
            self.gpuAlloc.freeGpuBuffer(gpuBuffer.buffer, gpuBuffer.allocation);
            self.gpuBuffers.removeAtKey(resourceId);
            self.resourceTypes[resourceId] = .None;
        }
    }
};
