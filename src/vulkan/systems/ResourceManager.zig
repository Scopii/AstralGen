const CreateStableMapArray = @import("../../structures/StableMapArray.zig").CreateStableMapArray;
const PushConstants = @import("../components/PushConstants.zig").PushConstants;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const ResourceSlot = @import("../components/PushConstants.zig").ResourceSlot;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const Texture = @import("../components/Texture.zig").Texture;
const Buffer = @import("../components/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const FrameData = @import("../../App.zig").FrameData;
const Pass = @import("../components/Pass.zig").Pass;
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const std = @import("std");

pub const Transfer = struct {
    srcOffset: u64,
    dstResId: Buffer.BufId,
    size: u64,
};

pub const ResourceManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: GpuAllocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,

    buffers: CreateStableMapArray(Buffer, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    textures: CreateStableMapArray(Texture, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    descMan: DescriptorManager,

    stagingBuffer: Buffer,
    stagingOffset: u64 = 0,
    transfers: std.array_list.Managed(Transfer),

    indirectBufIds: std.array_list.Managed(Buffer.BufId),

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
            .stagingBuffer = try gpuAlloc.allocStagingBuffer(rc.STAGING_BUF_SIZE),
            .transfers = std.array_list.Managed(Transfer).init(alloc),
            .indirectBufIds = std.array_list.Managed(Buffer.BufId).init(alloc),
            .textures = comptime CreateStableMapArray(Texture, rc.TEX_MAX, u32, rc.TEX_MAX, 0).init(),
            .buffers = comptime CreateStableMapArray(Buffer, rc.BUF_MAX, u32, rc.BUF_MAX, 0).init(),
        };
    }

    pub fn deinit(self: *ResourceManager) void {
        var bufIter = self.buffers.iterator();
        while (bufIter.next()) |key| {
            const buf = self.buffers.getPtr(key);
            self.gpuAlloc.freeBuffer(buf.handle, buf.allocation);
        }
        var texIter = self.textures.iterator();
        while (texIter.next()) |key| {
            const tex = self.textures.getPtr(key);
            self.gpuAlloc.freeTexture(tex);
        }
        self.descMan.deinit();
        self.transfers.deinit();
        self.gpuAlloc.freeBuffer(self.stagingBuffer.handle, self.stagingBuffer.allocation);
        self.indirectBufIds.deinit();
        self.gpuAlloc.deinit();
    }

    pub fn getBufferResourceSlot(self: *ResourceManager, bufId: Buffer.BufId) !ResourceSlot {
        if (self.buffers.isKeyUsed(bufId.val) != true) {
            std.debug.print("Tried getting Buffer ResourceSlot {} but its empty", .{bufId.val});
            return error.NoResourceSlot;
        }
        const bindlessIndex = self.buffers.getIndex(bufId.val);
        const buffer = self.buffers.getPtr(bufId.val);
        return ResourceSlot{ .index = bindlessIndex, .count = buffer.count };
    }

    pub fn getTextureResourceSlot(self: *ResourceManager, texId: Texture.TexId) !ResourceSlot {
        if (self.textures.isKeyUsed(texId.val) != true) {
            std.debug.print("Tried getting Texture ResourceSlot {} but its empty", .{texId.val});
            return error.NoResourceSlot;
        }
        const bindlessIndex = self.textures.getIndex(texId.val);
        return ResourceSlot{ .index = bindlessIndex, .count = 1 };
    }

    pub fn resetTransfers(self: *ResourceManager) void {
        self.stagingOffset = 0;
        self.transfers.clearRetainingCapacity();
    }

    pub fn queueBufferUpload(self: *ResourceManager, bufInf: Buffer.BufInf, bufId: Buffer.BufId, data: anytype) !void {
        const DataType = @TypeOf(data);
        const typeInfo = @typeInfo(DataType);

        const bytes: []const u8 = switch (typeInfo) {
            .pointer => |ptr| switch (ptr.size) {
                .one => std.mem.asBytes(data),
                .slice => std.mem.sliceAsBytes(data),
                else => return error.UnsupportedPointerType,
            },
            else => return error.ExpectedPointer,
        };

        if (self.stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        const stagingPtr: [*]u8 = @ptrCast(self.stagingBuffer.mappedPtr);
        @memcpy(stagingPtr[self.stagingOffset..][0..bytes.len], bytes);

        try self.transfers.append(Transfer{ .srcOffset = self.stagingOffset, .dstResId = bufId, .size = bytes.len });

        var buffer = try self.getBufferPtr(bufId);
        buffer.count = @intCast(bytes.len / bufInf.elementSize);
        self.stagingOffset += (bytes.len + 15) & ~@as(u64, 15); // Align the offset to 16 bytes for GPU safety
    }

    pub fn getTexturePtr(self: *ResourceManager, texId: Texture.TexId) !*Texture {
        if (self.textures.isKeyUsed(texId.val) == true) {
            return self.textures.getPtr(texId.val);
        } else return error.TextureIdNotUsed;
    }

    pub fn getBufferPtr(self: *ResourceManager, bufId: Buffer.BufId) !*Buffer {
        if (self.buffers.isKeyUsed(bufId.val) == true) {
            return self.buffers.getPtr(bufId.val);
        } else return error.BufferIdNotUsed;
    }

    pub fn createBuffer(self: *ResourceManager, bufInf: Buffer.BufInf) !void {
        const buffer = try self.gpuAlloc.allocDefinedBuffer(bufInf, bufInf.mem);
        const bindlessIndex = try self.buffers.insert(bufInf.id.val, buffer);
        try self.descMan.updateBufferDescriptor(buffer.gpuAddress, buffer.size, rc.STORAGE_BUF_BINDING, bindlessIndex);

        self.gpuAlloc.printMemoryLocation(buffer.allocation, self.gpu);
        std.debug.print("Buffer ID {} -> BindlessIndex {} created\n", .{ bufInf.id.val, bindlessIndex });

        if (bufInf.typ == .Indirect) {
            try self.indirectBufIds.append(bufInf.id);
            std.debug.print("and added to Indirect List\n", .{});
        } else std.debug.print("\n", .{});
    }

    pub fn createTexture(self: *ResourceManager, texInf: Texture.TexInf) !void {
        const tex = try self.gpuAlloc.allocTexture(texInf, texInf.mem);
        const bindlessIndex = try self.textures.insert(texInf.id.val, tex);

        if (texInf.typ == .Color) {
            try self.descMan.updateTextureDescriptor(tex.base.view, rc.STORAGE_TEX_BINDING, bindlessIndex);
        } else {
            try self.descMan.updateSampledTextureDescriptor(tex.base.view, rc.SAMPLED_TEX_BINDING, bindlessIndex);
        }
        std.debug.print("Texture ID {} -> BindlessIndex {} created\n", .{ texInf.id.val, bindlessIndex });
    }

    pub fn updateBuffer(self: *ResourceManager, bufInf: Buffer.BufInf, data: anytype) !void {
        if (bufInf.mem == .Gpu) {
            try self.queueBufferUpload(bufInf, bufInf.id, data);
        } else {
            const DataType = @TypeOf(data);
            const typeInfo = @typeInfo(DataType);

            const dataBytes: []const u8 = switch (typeInfo) {
                .pointer => |ptr| switch (ptr.size) {
                    .one => std.mem.asBytes(data),
                    .slice => std.mem.sliceAsBytes(data),
                    else => return error.UnsupportedPointerType,
                },
                else => return error.ExpectedPointer,
            };
            // Calculate element count
            const elementCount = dataBytes.len / bufInf.elementSize;
            if (dataBytes.len % bufInf.elementSize != 0) {
                std.debug.print("Error: Data size {} not aligned to element size {}\n", .{ dataBytes.len, bufInf.elementSize });
                return error.TypeMismatch;
            }

            var buffer = try self.getBufferPtr(bufInf.id);
            const pMappedData = buffer.mappedPtr orelse return error.BufferNotMapped;
            const destBytes: [*]u8 = @ptrCast(pMappedData);
            @memcpy(destBytes[0..dataBytes.len], dataBytes);
            buffer.count = @intCast(elementCount);
        }
    }

    pub fn replaceTexture(self: *ResourceManager, texId: Texture.TexId, nexTexInf: Texture.TexInf) !void {
        var oldTex = try self.getTexturePtr(texId);
        oldTex.base.state = .{};
        self.gpuAlloc.freeTexture(oldTex);

        const newTex = try self.gpuAlloc.allocTexture(nexTexInf, .Gpu);
        const bindlessIndex = self.textures.getIndex(texId.val);
        try self.descMan.updateTextureDescriptor(newTex.base.view, rc.STORAGE_TEX_BINDING, bindlessIndex);

        oldTex.* = newTex;
        std.debug.print("Texture {} Resized/Replaced at Slot {}\n", .{ texId.val, bindlessIndex });
    }

    pub fn destroyTexture(self: *ResourceManager, texId: Texture.TexId) void {
        if (self.textures.isKeyUsed(texId.val) == false) {
            std.debug.print("Warning: Tried to destroy empty Texture ID {}\n", .{texId});
            return;
        }
        const tex = self.textures.getPtr(texId.val);
        self.gpuAlloc.freeTexture(tex);
        self.textures.remove(texId.val);
    }

    pub fn destroyBuffer(self: *ResourceManager, bufId: Buffer.BufId) void {
        if (self.buffers.isKeyUsed(bufId.val) == false) {
            std.debug.print("Warning: Tried to destroy empty Buffer ID {}\n", .{bufId});
            return;
        }
        const buffer = self.buffers.getPtr(bufId.val);
        self.gpuAlloc.freeBuffer(buffer.handle, buffer.allocation);
        self.buffers.remove(bufId.val);
    }
};