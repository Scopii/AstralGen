const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const ResourceSlot = @import("DescriptorManager.zig").ResourceSlot;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const ResourceState = @import("../RenderGraph.zig").ResourceState;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const rc = @import("../../configs/renderConfig.zig");
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;

pub const Resource = struct {
    resourceType: ResourceUnion,
    bindlessIndex: u32,
    state: ResourceState = .{},

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

    pub fn getResourceSlot(self: *Resource) ResourceSlot {
        var resSlot = ResourceSlot{};

        switch (self.resourceType) {
            .gpuBuf => |gpuBuf| {
                resSlot.index = self.bindlessIndex;
                resSlot.count = gpuBuf.count;
            },
            .gpuImg => |_| {
                resSlot.index = self.bindlessIndex;
                resSlot.count = 1;
            },
        }
        return resSlot;
    }
};

pub const PendingTransfer = struct {
    srcOffset: u64,
    dstResId: u32,
    size: u64,
};

pub const ResourceManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: GpuAllocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,
    resources: CreateMapArray(Resource, rc.GPU_RESOURCE_MAX, u32, rc.GPU_RESOURCE_MAX, 0) = .{},
    nextImageIndex: u32 = 0,
    nextBufferIndex: u32 = 0,
    nextSampledImageIndex: u32 = 0,
    descMan: DescriptorManager,

    stagingBuffer: Resource.GpuBuffer,
    stagingPtr: [*]u8, // Mapped pointer for fast copying
    stagingOffset: u64 = 0,
    pendingTransfers: std.array_list.Managed(PendingTransfer),

    pub fn init(alloc: Allocator, context: *const Context) !ResourceManager {
        const gpi = context.gpi;
        const gpu = context.gpu;
        const gpuAlloc = try GpuAllocator.init(context.instance, context.gpi, context.gpu);

        const stagingSize = 32 * 1024 * 1024;
        const staging = try gpuAlloc.allocBuffer(
            stagingSize,
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VMA_MEMORY_USAGE_CPU_ONLY,
            vk.VMA_ALLOCATION_CREATE_MAPPED_BIT | vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
        );

        return .{
            .cpuAlloc = alloc,
            .gpuAlloc = gpuAlloc,
            .gpi = gpi,
            .gpu = gpu,
            .descMan = try DescriptorManager.init(alloc, gpuAlloc, gpi, gpu),
            .stagingBuffer = staging,
            .stagingPtr = @ptrCast(staging.allocInf.pMappedData.?),
            .pendingTransfers = std.array_list.Managed(PendingTransfer).init(alloc),
        };
    }

    pub fn deinit(self: *ResourceManager) void {
        while (self.resources.getCount() > 0) {
            self.destroyResource(self.resources.getKeyFromIndex(0));
        }
        self.descMan.deinit();

        self.pendingTransfers.deinit();
        self.gpuAlloc.freeGpuBuffer(self.stagingBuffer.buffer, self.stagingBuffer.allocation);

        self.gpuAlloc.deinit();
    }

    pub fn resetTransfers(self: *ResourceManager) void {
        self.stagingOffset = 0;
        self.pendingTransfers.clearRetainingCapacity();
    }

    pub fn queueBufferUpload(self: *ResourceManager, resInf: rc.ResourceInf, id: u32, data: anytype) !void {
        const DataType = @TypeOf(data);
        const typeInfo = @typeInfo(DataType);

        // Convert anytype to a byte slice safely
        const bytes: []const u8 = switch (typeInfo) {
            .pointer => |ptr| switch (ptr.size) {
                .one => std.mem.asBytes(data), // For &singleStruct
                .slice => std.mem.sliceAsBytes(data), // For slices/arrays
                else => return error.UnsupportedPointerType,
            },
            else => return error.ExpectedPointer,
        };

        if (self.stagingOffset + bytes.len > 1 * 1024 * 1024) return error.StagingBufferFull;

        // Copy CPU data into the staging area
        @memcpy(self.stagingPtr[self.stagingOffset..][0..bytes.len], bytes);

        try self.pendingTransfers.append(.{
            .srcOffset = self.stagingOffset,
            .dstResId = id,
            .size = bytes.len,
        });

        var resource = try self.getResourcePtr(id);
        if (resource.resourceType == .gpuBuf) {
            resource.resourceType.gpuBuf.count = @intCast(bytes.len / resInf.inf.bufInf.dataSize);
        }

        // Align the offset to 16 bytes for GPU safety
        self.stagingOffset += (bytes.len + 15) & ~@as(u64, 15);
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
                var bindlessIndex: u32 = undefined;
                const img = try self.gpuAlloc.allocGpuImage(imgInf, resInf.memUse);

                if (imgInf.imgType == .Color) {
                    bindlessIndex = self.nextImageIndex;
                    self.nextImageIndex += 1;
                    try self.descMan.updateImageDescriptor(img.view, rc.STORAGE_IMG_BINDING, bindlessIndex);
                } else {
                    bindlessIndex = self.nextSampledImageIndex;
                    self.nextSampledImageIndex += 1;
                    try self.descMan.updateSampledImageDescriptor(img.view, rc.SAMPLED_IMG_BINDING, bindlessIndex);
                }
                const finalRes = Resource{ .resourceType = .{ .gpuImg = img }, .bindlessIndex = bindlessIndex };
                self.resources.set(resInf.id, finalRes);
                std.debug.print("Image created. ID: {} -> BindlessIndex: {}\n", .{ resInf.id, bindlessIndex });
            },
            .bufInf => |bufInf| {
                const bindlessIndex = self.nextBufferIndex;
                self.nextBufferIndex += 1;

                const buffer = try self.gpuAlloc.allocDefinedBuffer(bufInf, resInf.memUse);
                try self.descMan.updateBufferDescriptor(buffer, rc.STORAGE_BUF_BINDING, bindlessIndex);

                const finalRes = Resource{ .resourceType = .{ .gpuBuf = buffer }, .bindlessIndex = bindlessIndex };
                self.gpuAlloc.printMemoryLocation(finalRes.resourceType.gpuBuf.allocation, self.gpu);
                self.resources.set(resInf.id, finalRes);
                std.debug.print("Buffer created. ID: {} -> BindlessIndex: {}\n", .{ resInf.id, bindlessIndex });
            },
        }
    }

    pub fn updateResource(self: *ResourceManager, resource: rc.ResourceInf, data: anytype) !void {
        switch (resource.inf) {
            .imgInf => |_| {},
            .bufInf => |bufInf| if (resource.memUse == .Gpu) {
                try self.queueBufferUpload(resource, resource.id, data);
            } else {
                try self.updateBuffer(bufInf, data, resource.id);
            },
        }
    }

    pub fn replaceResource(self: *ResourceManager, gpuId: u32, newInf: rc.ResourceInf.ImgInf) !void {
        var oldRes = self.resources.get(gpuId);
        oldRes.state = .{};
        const slotIndex = oldRes.bindlessIndex;

        self.gpuAlloc.freeGpuImage(oldRes.resourceType.gpuImg);
        const newGpuImg = try self.gpuAlloc.allocGpuImage(newInf, .Gpu);
        try self.descMan.updateImageDescriptor(newGpuImg.view, rc.STORAGE_IMG_BINDING, slotIndex);

        oldRes.resourceType = .{ .gpuImg = newGpuImg };
        self.resources.set(gpuId, oldRes);
        std.debug.print("Resource {} Resized/Replaced at Slot {}\n", .{ gpuId, slotIndex });
    }

    fn updateBuffer(self: *ResourceManager, bufInf: rc.ResourceInf.BufInf, data: anytype, gpuId: u32) !void {
        const DataType = @TypeOf(data);
        const typeInfo = @typeInfo(DataType);

        // Convert to byte slice based on input type
        const dataBytes: []const u8 = switch (typeInfo) {
            .pointer => |ptr| switch (ptr.size) {
                .one => std.mem.asBytes(data), // *T or *[N]T
                .slice => std.mem.sliceAsBytes(data), // []T
                else => return error.UnsupportedPointerType,
            },
            else => return error.ExpectedPointer,
        };

        // Calculate element count
        const elementCount = dataBytes.len / bufInf.dataSize;
        if (dataBytes.len % bufInf.dataSize != 0) {
            std.debug.print("Error: Data size {} not aligned to element size {}\n", .{ dataBytes.len, bufInf.dataSize });
            return error.TypeMismatch;
        }

        var resource = try self.getResourcePtr(gpuId);

        switch (resource.resourceType) {
            .gpuBuf => |*buffer| {
                const pMappedData = buffer.allocInf.pMappedData;

                if (pMappedData == null) {
                    return error.BufferNotMapped;
                }

                // Copy bytes
                const destBytes: [*]u8 = @ptrCast(pMappedData);
                @memcpy(destBytes[0..dataBytes.len], dataBytes);

                buffer.count = @intCast(elementCount);
                self.resources.set(gpuId, .{ .resourceType = .{ .gpuBuf = buffer.* }, .bindlessIndex = resource.bindlessIndex });
            },
            else => return error.WrongResourceType,
        }
    }

    pub fn destroyResource(self: *ResourceManager, gpuId: u32) void {
        if (self.resources.isKeyUsed(gpuId) != true) {
            std.debug.print("Warning: Tried to destroy empty Resource ID {}\n", .{gpuId});
            return;
        }
        const resource = self.resources.getPtr(gpuId);

        switch (resource.resourceType) {
            .gpuImg => |img| self.gpuAlloc.freeGpuImage(img),
            .gpuBuf => |buf| self.gpuAlloc.freeGpuBuffer(buf.buffer, buf.allocation),
        }
        self.resources.removeAtKey(gpuId);
    }
};
