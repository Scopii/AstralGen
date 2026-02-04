const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const DescriptorMan = @import("DescriptorMan.zig").DescriptorMan;
const PushData = @import("../types/res/PushData.zig").PushData;
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
        for (0..rc.MAX_IN_FLIGHT) |i| stagingBuffers[i] = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE);

        var transfers: [rc.MAX_IN_FLIGHT]std.array_list.Managed(Transfer) = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| transfers[i] = std.array_list.Managed(Transfer).init(alloc);

        return .{
            .vma = vma,
            .descMan = try DescriptorMan.init(vma, context.gpi, context.gpu),
            .stagingBuffers = stagingBuffers,
            .transfers = transfers,
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        for (self.buffers.getElements()) |*buf| self.vma.freeBuffer(buf.handle, buf.allocation);
        for (self.textures.getElements()) |*tex| self.vma.freeTexture(tex);
        for (&self.stagingBuffers) |*stagingBuffer| self.vma.freeBuffer(stagingBuffer.handle, stagingBuffer.allocation);
        for (&self.transfers) |*transferList| transferList.deinit();
        self.descMan.deinit(self.vma);
        self.vma.deinit();
    }

    pub fn getBufferResourceSlot(self: *ResourceMan, bufId: Buffer.BufId, flightId: u8) !PushData.ResourceSlot {
        const buf = try self.getBufferPtr(bufId);
        const updateFlightId = if (buf.typ == .Indirect) flightId else buf.lastUpdateFlightId;
        return .{ .index = buf.descIndex[updateFlightId], .count = buf.count };
    }

    pub fn getTextureResourceSlot(self: *ResourceMan, texId: Texture.TexId, flightId: u8) !PushData.ResourceSlot {
        const tex = try self.getTexturePtr(texId);
        return .{ .index = tex.descIndex[flightId], .count = 1 };
    }

    pub fn resetTransfers(self: *ResourceMan, flightId: u8) void {
        self.stagingOffsets[flightId] = 0;
        self.transfers[flightId].clearRetainingCapacity();
    }

    pub fn queueBufferUpload(self: *ResourceMan, bufInf: Buffer.BufInf, data: anytype, flightId: u8) !void {
        const DataType = @TypeOf(data);

        const bytes: []const u8 = switch (@typeInfo(DataType)) {
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

        const stagingPtr: [*]u8 = @ptrCast(stagingBuffer.mappedPtr);
        @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);

        var dstOffset: u64 = 0;

        if (bufInf.update == .PerFrame) {
            const sliceSize = @as(u64, bufInf.elementSize) * bufInf.len;
            dstOffset = @as(u64, flightId) * sliceSize; // Offset = FrameIndex * SliceSize
        }

        try self.transfers[flightId].append(Transfer{ .srcOffset = stagingOffset, .dstResId = bufInf.id, .dstOffset = dstOffset, .size = bytes.len });

        var buffer = try self.getBufferPtr(bufInf.id);
        buffer.count = @intCast(bytes.len / bufInf.elementSize);

        buffer.lastUpdateFlightId = flightId;

        self.stagingOffsets[flightId] += (bytes.len + 15) & ~@as(u64, 15);
    }

    pub fn getTexturePtr(self: *ResourceMan, texId: Texture.TexId) !*Texture {
        if (self.textures.isKeyUsed(texId.val) == true) return self.textures.getPtr(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn getBufferPtr(self: *ResourceMan, bufId: Buffer.BufId) !*Buffer {
        if (self.buffers.isKeyUsed(bufId.val) == true) return self.buffers.getPtr(bufId.val) else return error.BufferIdNotUsed;
    }

    pub fn createBuffer(self: *ResourceMan, bufInf: Buffer.BufInf) !void {
        switch (bufInf.update) {
            .Overwrite => {
                var buffer = try self.vma.allocDefinedBuffer(bufInf, bufInf.mem);
                const descIndex = try self.descMan.updateStorageBuffer(buffer.gpuAddress, buffer.size);
                for (&buffer.descIndex) |*index| {
                    index.* = descIndex;
                }
                self.buffers.set(bufInf.id.val, buffer);

                std.debug.print("Buffer ID {}, Type {}, Update: {} created! Descriptor Index {} ", .{ bufInf.id.val, bufInf.typ, bufInf.update, descIndex });
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
                    const descIndex = try self.descMan.updateStorageBuffer(buffer.gpuAddress + offset, sliceSize);
                    index.* = descIndex;
                }
                self.buffers.set(realBufInf.id.val, buffer);

                std.debug.print("Buffer ID {}, Type {}, Update {} created! Descriptor Indices ", .{ realBufInf.id.val, realBufInf.typ, realBufInf.update });
                for (buffer.descIndex) |index| std.debug.print("{} ", .{index});
                self.vma.printMemoryInfo(buffer.allocation);
            },
        }
    }

    pub fn createTexture(self: *ResourceMan, texInf: Texture.TexInf) !void {
        var tex = try self.vma.allocTexture(texInf);

        switch (texInf.typ) {
            .Color => {
                switch (texInf.update) {
                    .Overwrite => {
                        const descIndex = try self.descMan.updateStorageTexture(&tex.base[0]);
                        for (&tex.descIndex) |*index| index.* = descIndex;
                    },
                    .PerFrame => {
                        for (0..tex.descIndex.len) |i| {
                            const descIndex = try self.descMan.updateStorageTexture(&tex.base[i]);
                            tex.descIndex[i] = descIndex;
                        }
                    },
                }
            },
            .Depth, .Stencil => {
                switch (texInf.update) {
                    .Overwrite => {
                        const descIndex = try self.descMan.updateSampledTextureDescriptor(&tex.base[0]);
                        for (&tex.descIndex) |*index| index.* = descIndex;
                    },
                    .PerFrame => {
                        for (0..tex.descIndex.len) |i| {
                            const descIndex = try self.descMan.updateSampledTextureDescriptor(&tex.base[i]);
                            tex.descIndex[i] = descIndex;
                        }
                    },
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

                buffer.lastUpdateFlightId = flightId;
                // Update count (this updates the tracked count for the object)
                buffer.count = @intCast(elementCount);
            },
            .CpuRead => return error.CpuReadBufferCantUpdate,
        }
    }

    pub fn destroyTexture(self: *ResourceMan, texId: Texture.TexId) !void {
        const tex = try self.getTexturePtr(texId);
        self.vma.freeTexture(tex);
        self.textures.removeAtKey(texId.val);
    }

    pub fn destroyBuffer(self: *ResourceMan, bufId: Buffer.BufId) !void {
        const buf = try self.getBufferPtr(bufId);
        self.vma.freeBuffer(buf.handle, buf.allocation);
        self.buffers.removeAtKey(bufId.val);
    }
};
