const CreateStableMapArray = @import("../../structures/StableMapArray.zig").CreateStableMapArray;
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
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
    dstOffset: u64,
    size: u64,
};

pub const ResourceMan = struct {
    alloc: Allocator,
    vma: Vma,
    descMan: DescriptorMan,

    buffers: CreateMapArray(Buffer, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    textures: CreateMapArray(Texture, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    stagingBuffers: [rc.MAX_IN_FLIGHT]Buffer,
    stagingOffsets: [rc.MAX_IN_FLIGHT]u64 = .{0} ** rc.MAX_IN_FLIGHT,
    transfers: [rc.MAX_IN_FLIGHT]std.array_list.Managed(Transfer),

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const vma = try Vma.init(context.instance, context.gpi, context.gpu);

        var stagingBuffers: [rc.MAX_IN_FLIGHT]Buffer = undefined;
        for (0..stagingBuffers.len) |i| stagingBuffers[i] = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE);

        var transfers: [rc.MAX_IN_FLIGHT]std.array_list.Managed(Transfer) = undefined;
        for (0..transfers.len) |i| transfers[i] = std.array_list.Managed(Transfer).init(alloc);

        return .{
            .alloc = alloc,
            .vma = vma,
            .descMan = try DescriptorMan.init(vma, context.gpi, context.gpu),
            .stagingBuffers = stagingBuffers,
            .transfers = transfers,
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        const bufCount = self.buffers.getCount();
        for (0..bufCount) |i| {
            const buf = self.buffers.getPtrAtIndex(@intCast(i));
            self.vma.freeBuffer(buf.handle, buf.allocation);
        }
        const texCount = self.textures.getCount();
        for (0..texCount) |i| {
            const tex = self.textures.getPtrAtIndex(@intCast(i));
            self.vma.freeTexture(tex);
        }

        self.descMan.deinit(self.vma);
        for (&self.transfers) |*transferList| transferList.deinit();
        for (&self.stagingBuffers) |*stagingBuffer| self.vma.freeBuffer(stagingBuffer.handle, stagingBuffer.allocation);
        self.vma.deinit();
    }

    pub fn getBufferResourceSlot(self: *ResourceMan, bufId: Buffer.BufId, flightId: u8) !PushConstants.ResourceSlot {
        if (self.buffers.isKeyUsed(bufId.val) != true) {
            std.debug.print("Tried getting Buffer ID {} ResourceSlot but ID empty\n", .{bufId.val});
            return error.NoResourceSlot;
        }
        const buffer = self.buffers.getPtr(bufId.val);
        const updateFlightId = if (buffer.typ == .Indirect) flightId else buffer.lastUpdatedFlightId;
        return .{ .index = buffer.descIndex[updateFlightId], .count = buffer.count };
    }

    pub fn getTextureResourceSlot(self: *ResourceMan, texId: Texture.TexId, flightId: u8) !PushConstants.ResourceSlot {
        if (self.textures.isKeyUsed(texId.val) != true) {
            std.debug.print("Tried getting Texture ID {} ResourceSlot but ID empty\n", .{texId.val});
            return error.NoResourceSlot;
        }
        const tex = self.textures.getPtr(texId.val);
        return .{ .index = tex.descIndex[flightId], .count = 1 };
    }

    pub fn resetTransfers(self: *ResourceMan, flightId: u8) void {
        self.stagingOffsets[flightId] = 0;
        self.transfers[flightId].clearRetainingCapacity();
    }

    pub fn queueBufferUpload(self: *ResourceMan, bufInf: Buffer.BufInf, data: anytype, flightId: u8) !void {
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

        const stagingOffset = self.stagingOffsets[flightId];
        const stagingBuffer = self.stagingBuffers[flightId];

        if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        // Copy to Staging
        const stagingPtr: [*]u8 = @ptrCast(stagingBuffer.mappedPtr);
        @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);

        // Calculate Destination Offset Logic (NEW)
        var dstOffset: u64 = 0;

        if (bufInf.update == .PerFrame) {
            // Calculate size of one slice
            // bufInf.len is per frame length in config
            const sliceSize = @as(u64, bufInf.elementSize) * bufInf.len;
            dstOffset = @as(u64, flightId) * sliceSize; // Offset = FrameIndex * SliceSize
        }
        // Add to list with dstOffset
        try self.transfers[flightId].append(Transfer{ .srcOffset = stagingOffset, .dstResId = bufInf.id, .dstOffset = dstOffset, .size = bytes.len });
        // Update the buffer object CPU-side tracking
        var buffer = try self.getBufferPtr(bufInf.id);
        buffer.count = @intCast(bytes.len / bufInf.elementSize);

        buffer.lastUpdatedFlightId = flightId;

        self.stagingOffsets[flightId] += (bytes.len + 15) & ~@as(u64, 15);
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
        switch (bufInf.update) {
            .Overwrite => {
                var buffer = try self.vma.allocDefinedBuffer(bufInf, bufInf.mem);
                const bindlessIndex = self.descMan.updateBufferDescriptorFast(buffer.gpuAddress, buffer.size);
                for (&buffer.descIndex) |*index| {
                    index.* = bindlessIndex;
                }
                self.buffers.set(bufInf.id.val, buffer);

                std.debug.print("Buffer ID {}, Type {}, Update: {} created! Descriptor Index {} ", .{ bufInf.id.val, bufInf.typ, bufInf.update, bindlessIndex });
                self.vma.printMemoryInfo(buffer.allocation);
            },
            .PerFrame => {
                var realBufInf = bufInf;
                if (bufInf.update == .PerFrame) realBufInf.len *= rc.MAX_IN_FLIGHT;
                var buffer = try self.vma.allocDefinedBuffer(realBufInf, bufInf.mem);

                const totalSize = buffer.size;
                const sliceSize = totalSize / rc.MAX_IN_FLIGHT;

                for (&buffer.descIndex, 0..) |*index, i| {
                    const offset = @as(u64, i) * sliceSize;
                    const bindlessIndex = self.descMan.updateBufferDescriptorFast(buffer.gpuAddress + offset, sliceSize);
                    index.* = bindlessIndex;
                }
                self.buffers.set(realBufInf.id.val, buffer);

                std.debug.print("Buffer ID {}, Type {}, Update {} created! Descriptor Indices ", .{ realBufInf.id.val, realBufInf.typ, realBufInf.update });
                for (buffer.descIndex) |index| std.debug.print("{} ", .{index});
                self.vma.printMemoryInfo(buffer.allocation);
            },
            .Async => {},
        }
    }

    pub fn createTexture(self: *ResourceMan, texInf: Texture.TexInf) !void {
        var tex = try self.vma.allocTexture(texInf);

        switch (texInf.typ) {
            .Color => {
                for (0..tex.descIndex.len) |i| {
                    const bindlessIndex = try self.descMan.updateStorageTextureDescriptor(tex.base[i].view);
                    tex.descIndex[i] = bindlessIndex;
                }
            },
            .Depth, .Stencil => {
                for (0..tex.descIndex.len) |i| {
                    const bindlessIndex = try self.descMan.updateSampledTextureDescriptor(tex.base[i].view);
                    tex.descIndex[i] = bindlessIndex;
                }
            },
        }
        std.debug.print("Texture ID {}, Type {}, Update {} created! Descriptor Indices ", .{ texInf.id.val, texInf.typ, texInf.update });
        for (tex.descIndex) |index| std.debug.print("{} ", .{index});

        self.vma.printMemoryInfo(tex.allocation[0]);
        self.textures.set(texInf.id.val, tex);
    }

    pub fn getBufferDataPtr(self: *ResourceMan, bufId: Buffer.BufId, comptime T: type) !*T {
        const buffer = try self.getBufferPtr(bufId);
        if (buffer.mappedPtr) |ptr| return @as(*T, @ptrCast(@alignCast(ptr)));
        return error.BufferNotHostVisible;
    }

    pub fn printReadbackBuffer(self: *ResourceMan, bufId: Buffer.BufId, comptime T: type) !void {
        const readbackPtr = try self.getBufferDataPtr(bufId, T);
        std.debug.print("Readback: {}\n", .{readbackPtr.*});
    }

    pub fn updateBuffer(self: *ResourceMan, bufInf: Buffer.BufInf, data: anytype, flightId: u8) !void {
        switch (bufInf.mem) {
            .Gpu => {
                try self.queueBufferUpload(bufInf, data, flightId);
            },
            .CpuWrite => {
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

                // Calculate Destination Offset (Same logic as queueBufferUpload)
                var dstOffset: u64 = 0;
                if (bufInf.update == .PerFrame) {
                    // bufInf.len is the "per frame" length from config
                    const sliceSize = @as(u64, bufInf.elementSize) * bufInf.len;

                    // Safety Check: Ensure we aren't writing more than the slice allows
                    if (dataBytes.len > sliceSize) {
                        std.debug.print("Error: Updating Buffer {} with {} bytes, but PerFrame slice is only {} bytes\n", .{ bufInf.id.val, dataBytes.len, sliceSize });
                        return error.BufferOverflow;
                    }

                    dstOffset = @as(u64, flightId) * sliceSize;
                }
                // Apply Offset to Mapped Pointer
                const destBase: [*]u8 = @ptrCast(pMappedData);
                const destPtr = destBase + dstOffset;

                @memcpy(destPtr[0..dataBytes.len], dataBytes);

                buffer.lastUpdatedFlightId = flightId;
                // Update count (this updates the tracked count for the object)
                buffer.count = @intCast(elementCount);
            },
            .CpuRead => return error.CpuReadBufferCantUpdate,
        }
    }

    pub fn destroyTexture(self: *ResourceMan, texId: Texture.TexId) void {
        if (self.textures.isKeyUsed(texId.val) == false) {
            std.debug.print("Warning: Tried to destroy empty Texture ID {}\n", .{texId});
            return;
        }
        const tex = self.textures.getPtr(texId.val);
        self.vma.freeTexture(tex);
        self.textures.removeAtKey(texId.val);
    }

    pub fn destroyBuffer(self: *ResourceMan, bufId: Buffer.BufId) void {
        if (self.buffers.isKeyUsed(bufId.val) == false) {
            std.debug.print("Warning: Tried to destroy empty Buffer ID {}\n", .{bufId});
            return;
        }
        const buffer = self.buffers.getPtr(bufId.val);
        self.vma.freeBuffer(buffer.handle, buffer.allocation);
        self.buffers.removeAtKey(bufId.val);
    }
};
