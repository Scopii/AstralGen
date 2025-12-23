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
        arrayIndex: u32,
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

    pub fn isResourceIdUsed(self: *ResourceManager, gpuId: u32) bool {
        return self.resources.isKeyUsed(gpuId);
    }

    pub fn getValidatedGpuResourcePtr(self: *ResourceManager, gpuId: u32, comptime expectedTag: std.meta.Tag(Resource.ResourceUnion)) !*std.meta.TagPayload(Resource.ResourceUnion, expectedTag) {
        if (!self.resources.isKeyUsed(gpuId)) return error.ResourceIdEmpty;

        const resource = self.resources.getPtr(gpuId);
        if (resource.resourceType == expectedTag) {
            return &@field(resource.resourceType, @tagName(expectedTag));
        } else return error.ResourceValidationFailed;
    }

    pub fn createResource(self: *ResourceManager, resInf: rc.ResourceInfo) !void {
        switch (resInf.info) {
            .imgInf => |imgInf| {
                const img = try self.gpuAlloc.allocGpuImage(imgInf.extent, imgInf.imgFormat, resInf.memUsage, imgInf.arrayIndex);
                try self.descMan.updateImageDescriptor(img.view, resInf.binding, imgInf.arrayIndex);
                self.resources.set(resInf.gpuId, .{ .resourceType = .{ .gpuImg = img } });
            },
            .bufInf => |bufInf| {
                const buffer = try self.gpuAlloc.allocDefinedBuffer(bufInf, resInf.memUsage);
                try self.descMan.updateBufferDescriptor(buffer, resInf.binding, 0);
                self.resources.set(resInf.gpuId, .{ .resourceType = .{ .gpuBuf = buffer } });
            },
        }
        std.debug.print("Gpu Resource created with {s} gpuId {} binding {}\n", .{ @tagName(resInf.info), resInf.gpuId, resInf.binding });
    }

    pub fn updateResource(self: *ResourceManager, resource: rc.ResourceInfo, data: anytype) !void {
        switch (resource.info) {
            .imgInf => |_| {},
            .bufInf => |bufInf| try self.updateBuffer(bufInf, data, resource.gpuId),
        }
    }

    pub fn updateBuffer(self: *ResourceManager, bufInf: rc.ResourceInfo.BufInf, data: anytype, gpuId: u32) !void {
        const T = std.meta.Child(@TypeOf(data));
        if (@sizeOf(T) != bufInf.sizeOfElement) {
            std.debug.print("Error: Size mismatch! Config expects {} bytes, Data is {} bytes\n", .{ bufInf.sizeOfElement, @sizeOf(T) });
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
