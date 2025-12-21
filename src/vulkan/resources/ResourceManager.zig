const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
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
        while (self.gpuImages.getCount() > 0) self.destroyGpuResource(self.gpuImages.getKeyFromIndex(0));
        while (self.gpuBuffers.getCount() > 0) self.destroyGpuResource(self.gpuBuffers.getKeyFromIndex(0));
        self.descMan.deinit();
        self.gpuAlloc.deinit();
    }

    pub fn getGpuResourcePtr(self: *ResourceManager, resourceId: u32) !union(enum) { image: *GpuImage, buffer: *GpuBuffer } {
        switch (self.resourceTypes[resourceId]) {
            .Image => return .{ .image = self.gpuImages.getPtr(resourceId) },
            .Buffer => return .{ .buffer = self.gpuBuffers.getPtr(resourceId) },
            .None => return error.ResourceNotFound,
        }
    }

    pub fn getGpuBuffer(self: *ResourceManager, resourceId: u32) !GpuBuffer {
        if (self.resourceTypes[resourceId] == .None) return error.ResourceIdEmpty;
        if (self.resourceTypes[resourceId] != .Buffer) return error.ResourceIdNotBuffer;
        return self.gpuBuffers.get(resourceId);
    }

    pub fn getGpuImage(self: *ResourceManager, resourceId: u32) !GpuImage {
        if (self.resourceTypes[resourceId] == .None) return error.ResourceIdEmpty;
        if (self.resourceTypes[resourceId] != .Image) return error.ResourceIdNotImage;
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

    pub fn createGpuResource(self: *ResourceManager, resource: rc.GpuResource) !void {
        switch (resource) {
            .image => |imgInf| try self.createGpuImage(imgInf),
            .buffer => |buffInf| try self.createGpuBuffer(buffInf),
        }
    }

    fn createGpuImage(self: *ResourceManager, image: rc.GpuResource.ImageInfo) !void {
        const gpuImg = try self.gpuAlloc.allocGpuImage(image.extent, image.imgFormat, image.memUsage);
        self.gpuImages.set(image.resourceId, gpuImg);
        try self.descMan.updateImageDescriptor(gpuImg.view, image.resourceId);
        self.resourceTypes[image.resourceId] = .Image;
    }

    fn createGpuBuffer(self: *ResourceManager, bindingInf: rc.GpuResource.BufferInf) !void {
        const resourceId = bindingInf.binding;
        const buffer = try self.gpuAlloc.allocDefinedBuffer(bindingInf);
        self.gpuBuffers.set(bindingInf.binding, buffer);
        try self.descMan.updateBufferDescriptor(buffer, resourceId, 0);
        self.resourceTypes[resourceId] = .Buffer;
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

    pub fn destroyGpuResource(self: *ResourceManager, resourceId: u32) void {
        switch (self.resourceTypes[resourceId]) {
            .Image => {
                const gpuImg = self.gpuImages.get(resourceId);
                self.gpuAlloc.freeGpuImage(gpuImg);
                self.gpuImages.removeAtKey(resourceId);
            },
            .Buffer => {
                const gpuBuffer = self.gpuBuffers.get(resourceId);
                self.gpuAlloc.freeGpuBuffer(gpuBuffer.buffer, gpuBuffer.allocation);
                self.gpuBuffers.removeAtKey(resourceId);
            },
            .None => std.debug.print("Tried destroying Empty ResourceId {}\n", .{resourceId}),
        }
        self.resourceTypes[resourceId] = .None;
    }
};

pub const GpuImage = struct {
    allocation: vk.VmaAllocation,
    img: vk.VkImage,
    view: vk.VkImageView,
    extent3d: vk.VkExtent3D,
    format: vk.VkFormat,
    curLayout: u32 = vk.VK_IMAGE_LAYOUT_UNDEFINED,
};

pub const GpuBuffer = struct {
    pub const deviceAddress = u64;
    allocation: vk.VmaAllocation,
    allocInf: vk.VmaAllocationInfo,
    buffer: vk.VkBuffer,
    gpuAddress: deviceAddress,
    count: u32 = 0,
};
