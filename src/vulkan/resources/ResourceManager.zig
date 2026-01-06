const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const Texture = @import("Texture.zig").Texture;
const Buffer = @import("Buffer.zig").Buffer;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
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

    buffers: CreateMapArray(Buffer, rc.GPU_BUF_MAX, u32, rc.GPU_BUF_MAX, 0) = .{},
    textures: CreateMapArray(Texture, rc.GPU_IMG_MAX, u32, rc.GPU_IMG_MAX, 0) = .{},

    nextTextureIndex: u32 = 0,
    nextBufferIndex: u32 = 0,
    nextSampledTextureIndex: u32 = 0,
    descMan: DescriptorManager,

    stagingBuffer: Buffer,
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
            self.destroyTexture(self.textures.getKeyFromIndex(0));
        }

        self.descMan.deinit();

        self.pendingTransfers.deinit();
        self.gpuAlloc.freeBuffer(self.stagingBuffer.handle, self.stagingBuffer.allocation);

        self.gpuAlloc.deinit();
    }

    pub fn resetTransfers(self: *ResourceManager) void {
        self.stagingOffset = 0;
        self.pendingTransfers.clearRetainingCapacity();
    }

    pub fn queueBufferUpload(self: *ResourceManager, bufInf: Buffer.BufInf, bufId: u32, data: anytype) !void {
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
            .dstResId = bufId,
            .size = bytes.len,
        });

        var buffer = try self.getBufferPtr(bufId);
        buffer.count = @intCast(bytes.len / bufInf.dataSize);

        // Align the offset to 16 bytes for GPU safety
        self.stagingOffset += (bytes.len + 15) & ~@as(u64, 15);
    }

    pub fn getTexturePtr(self: *ResourceManager, texId: u32) !*Texture {
        if (self.textures.isKeyUsed(texId) == true) {
            return self.textures.getPtr(texId);
        } else return error.TextureIdNotUsed;
    }

    pub fn getBufferPtr(self: *ResourceManager, bufId: u32) !*Buffer {
        if (self.buffers.isKeyUsed(bufId) == true) {
            return self.buffers.getPtr(bufId);
        } else return error.BufferIdNotUsed;
    }

    pub fn createBuffer(self: *ResourceManager, bufInf: Buffer.BufInf) !void {
        const bindlessIndex = self.nextBufferIndex;
        self.nextBufferIndex += 1;

        var buffer = try self.gpuAlloc.allocDefinedBuffer(bufInf, bufInf.memUse);
        buffer.bindlessIndex = bindlessIndex;
        try self.descMan.updateBufferDescriptor(buffer, rc.STORAGE_BUF_BINDING, bindlessIndex);

        self.gpuAlloc.printMemoryLocation(buffer.allocation, self.gpu);
        self.buffers.set(bufInf.bufId, buffer);
        std.debug.print("Buffer created. ID: {} -> BindlessIndex: {}\n", .{ bufInf.bufId, bindlessIndex });
    }

    pub fn createTexture(self: *ResourceManager, texInf: Texture.TexInf) !void {
        var bindlessIndex: u32 = undefined;
        var tex = try self.gpuAlloc.allocTexture(texInf, texInf.memUse);

        if (texInf.texType == .Color) {
            bindlessIndex = self.nextTextureIndex;
            self.nextTextureIndex += 1;
            try self.descMan.updateTextureDescriptor(tex.base.view, rc.STORAGE_IMG_BINDING, bindlessIndex);
        } else {
            bindlessIndex = self.nextSampledTextureIndex;
            self.nextSampledTextureIndex += 1;
            try self.descMan.updateSampledTextureDescriptor(tex.base.view, rc.SAMPLED_IMG_BINDING, bindlessIndex);
        }
        tex.bindlessIndex = bindlessIndex;

        self.textures.set(texInf.texId, tex);
        std.debug.print("Image created. ID: {} -> BindlessIndex: {}\n", .{ texInf.texId, bindlessIndex });
    }

    pub fn updateBuffer(self: *ResourceManager, bufInf: Buffer.BufInf, data: anytype) !void {
        if (bufInf.memUse == .Gpu) {
            try self.queueBufferUpload(bufInf, bufInf.bufId, data);
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

            var buffer = try self.getBufferPtr(bufInf.bufId);

            const pMappedData = buffer.allocInf.pMappedData orelse return error.BufferNotMapped;

            // Copy bytes
            const destBytes: [*]u8 = @ptrCast(pMappedData);
            @memcpy(destBytes[0..dataBytes.len], dataBytes);

            buffer.count = @intCast(elementCount);
        }
    }

    pub fn replaceTexture(self: *ResourceManager, texId: u32, nexTexInf: Texture.TexInf) !void {
        var oldTex = try self.getTexturePtr(texId);
        oldTex.base.state = .{};
        const slotIndex = oldTex.bindlessIndex;

        self.gpuAlloc.freeTexture(oldTex.*);
        const newTex = try self.gpuAlloc.allocTexture(nexTexInf, .Gpu);
        try self.descMan.updateTextureDescriptor(newTex.base.view, rc.STORAGE_IMG_BINDING, slotIndex);

        oldTex.* = newTex;
        std.debug.print("Resource {} Resized/Replaced at Slot {}\n", .{ texId, slotIndex });
    }

    pub fn destroyTexture(self: *ResourceManager, texId: u32) void {
        if (self.textures.isKeyUsed(texId) != true) {
            std.debug.print("Warning: Tried to destroy empty Resource ID {}\n", .{texId});
            return;
        }
        const tex = self.textures.getPtr(texId);
        self.gpuAlloc.freeTexture(tex.*);
        self.textures.removeAtKey(texId);
    }

    pub fn destroyBuffer(self: *ResourceManager, bufId: u32) void {
        if (self.buffers.isKeyUsed(bufId) != true) {
            std.debug.print("Warning: Tried to destroy empty Resource ID {}\n", .{bufId});
            return;
        }
        const buffer = self.buffers.getPtr(bufId);
        self.gpuAlloc.freeBuffer(buffer.handle, buffer.allocation);
        self.buffers.removeAtKey(bufId);
    }
};
