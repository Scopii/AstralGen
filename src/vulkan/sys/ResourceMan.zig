const CreateStableMapArray = @import("../../structures/StableMapArray.zig").CreateStableMapArray;
const PushConstants = @import("../types/res/PushConstants.zig").PushConstants;
const DescriptorMan = @import("DescriptorMan.zig").DescriptorMan;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

pub const Transfer = struct {
    srcOffset: u64,
    dstResId: Buffer.BufId,
    size: u64,
};

pub const ResourceMan = struct {
    alloc: Allocator,
    vma: Vma,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,

    buffers: CreateStableMapArray(Buffer, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    textures: CreateStableMapArray(Texture, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    descMan: DescriptorMan,

    stagingBuffer: Buffer,
    stagingOffset: u64 = 0,
    transfers: std.array_list.Managed(Transfer),

    indirectBufIds: std.array_list.Managed(Buffer.BufId),

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const gpi = context.gpi;
        const gpu = context.gpu;
        const gpuAlloc = try Vma.init(context.instance, context.gpi, context.gpu);

        return .{
            .alloc = alloc,
            .vma = gpuAlloc,
            .gpi = gpi,
            .gpu = gpu,
            .descMan = try DescriptorMan.init(alloc, gpuAlloc, gpi, gpu),
            .stagingBuffer = try gpuAlloc.allocStagingBuffer(rc.STAGING_BUF_SIZE),
            .transfers = std.array_list.Managed(Transfer).init(alloc),
            .indirectBufIds = std.array_list.Managed(Buffer.BufId).init(alloc),
            .textures = comptime CreateStableMapArray(Texture, rc.TEX_MAX, u32, rc.TEX_MAX, 0).init(),
            .buffers = comptime CreateStableMapArray(Buffer, rc.BUF_MAX, u32, rc.BUF_MAX, 0).init(),
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        var bufIter = self.buffers.iterator();
        while (bufIter.next()) |key| {
            const buf = self.buffers.getPtr(key);
            self.vma.freeBuffer(buf.handle, buf.allocation);
        }
        var texIter = self.textures.iterator();
        while (texIter.next()) |key| {
            const tex = self.textures.getPtr(key);
            self.vma.freeTexture(tex);
        }
        self.descMan.deinit();
        self.transfers.deinit();
        self.vma.freeBuffer(self.stagingBuffer.handle, self.stagingBuffer.allocation);
        self.indirectBufIds.deinit();
        self.vma.deinit();
    }

    pub fn getBufferResourceSlot(self: *ResourceMan, bufId: Buffer.BufId) !PushConstants.ResourceSlot {
        if (self.buffers.isKeyUsed(bufId.val) != true) {
            std.debug.print("Tried getting Buffer ResourceSlot {} but its empty\n", .{bufId.val});
            return error.NoResourceSlot;
        }
        const bindlessIndex = self.buffers.getIndex(bufId.val);
        const buffer = self.buffers.getPtr(bufId.val);
        return .{ .index = bindlessIndex, .count = buffer.count };
    }

    pub fn getTextureResourceSlot(self: *ResourceMan, texId: Texture.TexId) !PushConstants.ResourceSlot {
        if (self.textures.isKeyUsed(texId.val) != true) {
            std.debug.print("Tried getting Texture ResourceSlot {} but its empty\n", .{texId.val});
            return error.NoResourceSlot;
        }
        const bindlessIndex = self.textures.getIndex(texId.val);
        return .{ .index = bindlessIndex, .count = 1 };
    }

    pub fn resetTransfers(self: *ResourceMan) void {
        self.stagingOffset = 0;
        self.transfers.clearRetainingCapacity();
    }

    pub fn queueBufferUpload(self: *ResourceMan, bufInf: Buffer.BufInf, data: anytype) !void {
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

        try self.transfers.append(Transfer{ .srcOffset = self.stagingOffset, .dstResId = bufInf.id, .size = bytes.len });

        var buffer = try self.getBufferPtr(bufInf.id);
        buffer.count = @intCast(bytes.len / bufInf.elementSize);
        self.stagingOffset += (bytes.len + 15) & ~@as(u64, 15); // Align the offset to 16 bytes for GPU safety
    }

    pub fn getTexturePtr(self: *ResourceMan, texId: Texture.TexId) !*Texture {
        if (self.textures.isKeyUsed(texId.val) == true) {
            return self.textures.getPtr(texId.val);
        } else return error.TextureIdNotUsed;
    }

    pub fn getBufferPtr(self: *ResourceMan, bufId: Buffer.BufId) !*Buffer {
        if (self.buffers.isKeyUsed(bufId.val) == true) {
            return self.buffers.getPtr(bufId.val);
        } else return error.BufferIdNotUsed;
    }

    pub fn createBuffer(self: *ResourceMan, bufInf: Buffer.BufInf) !void {
        const buffer = try self.vma.allocDefinedBuffer(bufInf, bufInf.mem);
        const bindlessIndex = try self.buffers.insert(bufInf.id.val, buffer);
        self.descMan.updateBufferDescriptorFast(buffer.gpuAddress, buffer.size, bindlessIndex);

        self.vma.printMemoryLocation(buffer.allocation, self.gpu);
        std.debug.print("Buffer ID {} -> BindlessIndex {} created", .{ bufInf.id.val, bindlessIndex });

        if (bufInf.typ == .Indirect) {
            try self.indirectBufIds.append(bufInf.id);
            std.debug.print(" and added to Indirect List\n", .{});
        } else std.debug.print("\n", .{});
    }

    pub fn createTexture(self: *ResourceMan, texInf: Texture.TexInf) !void {
        const tex = try self.vma.allocTexture(texInf, texInf.mem);
        const bindlessIndex = try self.textures.insert(texInf.id.val, tex);

        if (texInf.typ == .Color) {
            try self.descMan.updateTextureDescriptor(tex.base.view, bindlessIndex);
        } else {
            try self.descMan.updateSampledTextureDescriptor(tex.base.view, bindlessIndex);
        }
        std.debug.print("Texture ID {} -> BindlessIndex {} created\n", .{ texInf.id.val, bindlessIndex });
    }

    pub fn getBufferDataPtr(self: *ResourceMan, bufId: Buffer.BufId, comptime T: type) !*T {
        const buffer = try self.getBufferPtr(bufId);
        if (buffer.mappedPtr) |ptr| return @as(*T, @ptrCast(@alignCast(ptr)));
        return error.BufferNotHostVisible;
    }

    pub fn printReadback(self: *ResourceMan, bufId: Buffer.BufId, comptime T: type) !void {
        const readbackPtr = try self.getBufferDataPtr(bufId, T);
        std.debug.print("Readback: {}\n", .{readbackPtr.*});
    }

    pub fn updateBuffer(self: *ResourceMan, bufInf: Buffer.BufInf, data: anytype) !void {
        if (bufInf.mem == .Gpu) {
            try self.queueBufferUpload(bufInf, data);
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

    pub fn replaceTexture(self: *ResourceMan, texId: Texture.TexId, nexTexInf: Texture.TexInf) !void {
        var oldTex = try self.getTexturePtr(texId);
        oldTex.base.state = .{};
        self.vma.freeTexture(oldTex);

        const newTex = try self.vma.allocTexture(nexTexInf, .Gpu);
        const bindlessIndex = self.textures.getIndex(texId.val);
        try self.descMan.updateTextureDescriptor(newTex.base.view, bindlessIndex);

        oldTex.* = newTex;
        std.debug.print("Texture {} Resized/Replaced at Slot {}\n", .{ texId.val, bindlessIndex });
    }

    pub fn destroyTexture(self: *ResourceMan, texId: Texture.TexId) void {
        if (self.textures.isKeyUsed(texId.val) == false) {
            std.debug.print("Warning: Tried to destroy empty Texture ID {}\n", .{texId});
            return;
        }
        const tex = self.textures.getPtr(texId.val);
        self.vma.freeTexture(tex);
        self.textures.remove(texId.val);
    }

    pub fn destroyBuffer(self: *ResourceMan, bufId: Buffer.BufId) void {
        if (self.buffers.isKeyUsed(bufId.val) == false) {
            std.debug.print("Warning: Tried to destroy empty Buffer ID {}\n", .{bufId});
            return;
        }
        const buffer = self.buffers.getPtr(bufId.val);
        self.vma.freeBuffer(buffer.handle, buffer.allocation);
        self.buffers.remove(bufId.val);
    }
};