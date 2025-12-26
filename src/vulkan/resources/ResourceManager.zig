const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const Object = @import("../../ecs/EntityManager.zig").Object;
const rc = @import("../../configs/renderConfig.zig");
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;

pub const Resource = struct {
    resourceType: ResourceUnion,

    pub const ResourceUnion = union(enum) {
        gpuBuf: GpuBuffer,
        gpuImg: GpuImage,
    };
    pub const GpuImage = struct {
        imgInf: rc.ResourceInf.ImgInf,
        allocation: vk.VmaAllocation,
        img: vk.VkImage,
        view: vk.VkImageView,
    };
    pub const GpuBuffer = struct {
        allocation: vk.VmaAllocation,
        allocInf: vk.VmaAllocationInfo,
        buffer: vk.VkBuffer,
        gpuAddress: u64,
        count: u32 = 0,
    };
};

pub const ResourceManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: GpuAllocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,
    resources: CreateMapArray(Resource, rc.GPU_RESOURCE_MAX, u32, rc.GPU_RESOURCE_MAX, 0) = .{},
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
        while (self.resources.getCount() > 0) {
            self.destroyResource(self.resources.getKeyFromIndex(0));
        }
        self.descMan.deinit();
        self.gpuAlloc.deinit();
    }

    pub fn getResourcePtr(self: *ResourceManager, gpuId: u32) !*Resource {
        if (self.resources.isKeyUsed(gpuId) == false) return error.ResourceIdEmpty;
        return self.resources.getPtr(gpuId);
    }

    pub fn getImagePtr(self: *ResourceManager, gpuId: u32) !*Resource.GpuImage {
        const resource = try self.getResourcePtr(gpuId);
        switch (resource.resourceType) {
            .gpuImg => |*gpuImg| return gpuImg,
            else => {
                std.debug.print("Warning: Tried getting GPU Image but Resource {} is not an Image\n", .{gpuId});
                return error.WrongResourceType;
            },
        }
    }

    pub fn getBufferPtr(self: *ResourceManager, gpuId: u32) !*Resource.GpuBuffer {
        const resource = try self.getResourcePtr(gpuId);
        switch (resource.resourceType) {
            .gpuBuf => |*gpuBuf| return gpuBuf,
            else => {
                std.debug.print("Warning: Tried getting GPU Buffer but Resource {} is not an Buffer\n", .{gpuId});
                return error.WrongResourceType;
            },
        }
    }

    pub fn isResourceIdUsed(self: *ResourceManager, gpuId: u32) bool {
        return self.resources.isKeyUsed(gpuId);
    }

    fn getValidResourcePtr(self: *ResourceManager, gpuId: u32, comptime expectedTag: std.meta.Tag(Resource.ResourceUnion)) !*std.meta.TagPayload(Resource.ResourceUnion, expectedTag) {
        if (!self.resources.isKeyUsed(gpuId)) return error.ResourceIdEmpty;

        const resource = self.resources.getPtr(gpuId);
        if (resource.resourceType == expectedTag) {
            return &@field(resource.resourceType, @tagName(expectedTag));
        } else return error.ResourceValidationFailed;
    }

    pub fn createResource(self: *ResourceManager, resInf: rc.ResourceInf) !void {
        switch (resInf.inf) {
            .imgInf => |imgInf| {
                const img = try self.gpuAlloc.allocGpuImage(imgInf, resInf.memUse);
                try self.descMan.updateImageDescriptor(img.view, resInf.binding, imgInf.arrayIndex);
                self.resources.set(resInf.id, .{ .resourceType = .{ .gpuImg = img } });
            },
            .bufInf => |bufInf| {
                const buffer = try self.gpuAlloc.allocDefinedBuffer(bufInf, resInf.memUse);
                try self.descMan.updateBufferDescriptor(buffer, resInf.binding, 0);
                self.resources.set(resInf.id, .{ .resourceType = .{ .gpuBuf = buffer } });
            },
        }
        std.debug.print("Gpu Resource created with {s} gpuId {} binding {}\n", .{ @tagName(resInf.inf), resInf.id, resInf.binding });
    }

    pub fn updateResource(self: *ResourceManager, resource: rc.ResourceInf, data: anytype) !void {
        switch (resource.inf) {
            .imgInf => |_| {},
            .bufInf => |bufInf| try self.updateBuffer(bufInf, data, resource.id),
        }
    }

    pub fn updateBuffer(self: *ResourceManager, bufInf: rc.ResourceInf.BufInf, data: anytype, gpuId: u32) !void {
        const T = std.meta.Child(@TypeOf(data));
        if (@sizeOf(T) != bufInf.dataSize) {
            std.debug.print("Error: Size mismatch! Config expects {} bytes, Data is {} bytes\n", .{ bufInf.dataSize, @sizeOf(T) });
            return error.TypeMismatch;
        }
        var resource = try self.getResourcePtr(gpuId);

        switch (resource.resourceType) {
            .gpuBuf => |*buffer| {
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
                self.resources.set(gpuId, .{ .resourceType = .{ .gpuBuf = buffer.* } });
            },
            else => std.debug.print("Warning: GPU Buffer Update failed because Resource {} is not a GPU Buffer", .{gpuId}),
        }
    }

    pub fn destroyResource(self: *ResourceManager, gpuId: u32) void {
        if (self.resources.isKeyUsed(gpuId) != true) {
            std.debug.print("Warning: Tried to destroy empty Resource ID {}\n", .{gpuId});
            return;
        }
        const resource = self.resources.getPtr(gpuId);

        switch (resource.resourceType) {
            .gpuImg => |img| {
                self.gpuAlloc.freeGpuImage(img);
            },
            .gpuBuf => |buf| {
                self.gpuAlloc.freeGpuBuffer(buf.buffer, buf.allocation);
            },
        }
        self.resources.removeAtKey(gpuId);
    }
};
