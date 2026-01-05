const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const ResourceSlot = @import("DescriptorManager.zig").ResourceSlot;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const Resource = @import("Resource.zig").Resource;
const ResourceInf = @import("Resource.zig").ResourceInf;
const ResourceState = @import("../RenderGraph.zig").ResourceState;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const rc = @import("../../configs/renderConfig.zig");
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;

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

    buffers: CreateMapArray(Resource, rc.GPU_BUF_MAX, u32, rc.GPU_BUF_MAX, 0) = .{},
    textures: CreateMapArray(Resource, rc.GPU_IMG_MAX, u32, rc.GPU_IMG_MAX, 0) = .{},

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
        while (self.buffers.getCount() > 0) {
            self.destroyBuffer(self.buffers.getKeyFromIndex(0));
        }
        while (self.textures.getCount() > 0) {
            self.destroyImage(self.textures.getKeyFromIndex(0));
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

    pub fn queueBufferUpload(self: *ResourceManager, resInf: ResourceInf, id: u32, data: anytype) !void {
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

        var buffer = try self.getBufferPtr(id);
        buffer.count = @intCast(bytes.len / resInf.inf.bufInf.dataSize);

        // Align the offset to 16 bytes for GPU safety
        self.stagingOffset += (bytes.len + 15) & ~@as(u64, 15);
    }

    pub fn getImagePtr(self: *ResourceManager, texId: u32) !*Resource.GpuImage {
        const image = self.textures.getPtr(texId);
        switch (image.resourceType) {
            .gpuImg => |*gpuImg| return gpuImg,
            else => {
                std.debug.print("Warning: Tried getting GPU Image but Resource {} is not an Image\n", .{texId});
                return error.WrongResourceType;
            },
        }
    }

    pub fn getBufferPtr(self: *ResourceManager, bufId: u32) !*Resource.GpuBuffer {
        const buffer = self.buffers.getPtr(bufId);
        switch (buffer.resourceType) {
            .gpuBuf => |*gpuBuf| return gpuBuf,
            else => {
                std.debug.print("Warning: Tried getting GPU Buffer but Resource {} is not an Buffer\n", .{bufId});
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

    pub fn createBuffer(self: *ResourceManager, resInf: ResourceInf) !void {
        switch (resInf.inf) {
            .imgInf => {},
            .bufInf => |bufInf| {
                const bindlessIndex = self.nextBufferIndex;
                self.nextBufferIndex += 1;

                var buffer = try self.gpuAlloc.allocDefinedBuffer(bufInf, resInf.memUse);
                buffer.bindlessIndex = bindlessIndex;
                try self.descMan.updateBufferDescriptor(buffer, rc.STORAGE_BUF_BINDING, bindlessIndex);

                const finalRes = Resource{ .resourceType = .{ .gpuBuf = buffer } };
                self.gpuAlloc.printMemoryLocation(finalRes.resourceType.gpuBuf.allocation, self.gpu);
                self.buffers.set(resInf.id, finalRes);
                std.debug.print("Buffer created. ID: {} -> BindlessIndex: {}\n", .{ resInf.id, bindlessIndex });
            },
        }
    }

    pub fn createImage(self: *ResourceManager, resInf: ResourceInf) !void {
        switch (resInf.inf) {
            .imgInf => |imgInf| {
                var bindlessIndex: u32 = undefined;
                var img = try self.gpuAlloc.allocGpuImage(imgInf, resInf.memUse);

                if (imgInf.imgType == .Color) {
                    bindlessIndex = self.nextImageIndex;
                    self.nextImageIndex += 1;
                    try self.descMan.updateImageDescriptor(img.view, rc.STORAGE_IMG_BINDING, bindlessIndex);
                } else {
                    bindlessIndex = self.nextSampledImageIndex;
                    self.nextSampledImageIndex += 1;
                    try self.descMan.updateSampledImageDescriptor(img.view, rc.SAMPLED_IMG_BINDING, bindlessIndex);
                }
                img.bindlessIndex = bindlessIndex;

                const finalRes = Resource{ .resourceType = .{ .gpuImg = img } };
                self.textures.set(resInf.id, finalRes);
                std.debug.print("Image created. ID: {} -> BindlessIndex: {}\n", .{ resInf.id, bindlessIndex });
            },
            .bufInf => {},
        }
    }

    pub fn updateImage(_: *ResourceManager, resource: ResourceInf, _: anytype) !void {
        switch (resource.inf) {
            .imgInf => |_| {},
            .bufInf => {},
        }
    }

    pub fn updateBuffer(self: *ResourceManager, resourceInf: ResourceInf, data: anytype) !void {
        switch (resourceInf.inf) {
            .imgInf => |_| {},
            .bufInf => |bufInf| if (resourceInf.memUse == .Gpu) {
                try self.queueBufferUpload(resourceInf, resourceInf.id, data);
            } else {
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

                var buffer = try self.getBufferPtr(resourceInf.id);

                const pMappedData = buffer.allocInf.pMappedData orelse return error.BufferNotMapped;

                // Copy bytes
                const destBytes: [*]u8 = @ptrCast(pMappedData);
                @memcpy(destBytes[0..dataBytes.len], dataBytes);

                buffer.count = @intCast(elementCount);
            },
        }
    }

    pub fn replaceImage(self: *ResourceManager, gpuId: u32, newInf: ResourceInf.ImgInf) !void {
        var oldImg = try self.getImagePtr(gpuId);
        oldImg.state = .{};
        const slotIndex = oldImg.bindlessIndex;

        self.gpuAlloc.freeGpuImage(oldImg.*);
        const newGpuImg = try self.gpuAlloc.allocGpuImage(newInf, .Gpu);
        try self.descMan.updateImageDescriptor(newGpuImg.view, rc.STORAGE_IMG_BINDING, slotIndex);

        oldImg.* = newGpuImg;
        self.textures.set(gpuId, Resource{ .resourceType = .{ .gpuImg = oldImg.* } });
        std.debug.print("Resource {} Resized/Replaced at Slot {}\n", .{ gpuId, slotIndex });
    }

    pub fn destroyImage(self: *ResourceManager, imgId: u32) void {
        if (self.textures.isKeyUsed(imgId) != true) {
            std.debug.print("Warning: Tried to destroy empty Resource ID {}\n", .{imgId});
            return;
        }
        const img = self.textures.getPtr(imgId);
        self.gpuAlloc.freeGpuImage(img.resourceType.gpuImg);
        self.textures.removeAtKey(imgId);
    }

    pub fn destroyBuffer(self: *ResourceManager, bufId: u32) void {
        if (self.buffers.isKeyUsed(bufId) != true) {
            std.debug.print("Warning: Tried to destroy empty Resource ID {}\n", .{bufId});
            return;
        }
        const buf = self.buffers.getPtr(bufId);
        const gpuBuf = buf.resourceType.gpuBuf; 
        self.gpuAlloc.freeGpuBuffer(gpuBuf.buffer, gpuBuf.allocation);
        self.buffers.removeAtKey(bufId);
    }
};
