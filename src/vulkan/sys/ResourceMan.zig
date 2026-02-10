const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
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

const BufferBase = @import("../types/res/BufferBase.zig").BufferBase;

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

    realFramesInFlights: [rc.MAX_IN_FLIGHT]u64 = .{0} ** rc.MAX_IN_FLIGHT,

    bufToDeleteLists: [rc.MAX_IN_FLIGHT + 1]FixedList(Buffer, rc.BUF_MAX),
    texToDeleteLists: [rc.MAX_IN_FLIGHT + 1]FixedList(Texture, rc.TEX_MAX),

    stagingBuffers: [rc.MAX_IN_FLIGHT]BufferBase,
    stagingOffsets: [rc.MAX_IN_FLIGHT]u64 = .{0} ** rc.MAX_IN_FLIGHT,
    transfers: [rc.MAX_IN_FLIGHT]std.array_list.Managed(Transfer),

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const vma = try Vma.init(context.instance, context.gpi, context.gpu);

        var stagingBuffers: [rc.MAX_IN_FLIGHT]BufferBase = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| stagingBuffers[i] = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE);

        var transfers: [rc.MAX_IN_FLIGHT]std.array_list.Managed(Transfer) = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| transfers[i] = std.array_list.Managed(Transfer).init(alloc);

        var bufToDeleteList: [rc.MAX_IN_FLIGHT + 1]FixedList(Buffer, rc.BUF_MAX) = undefined;
        for (0..bufToDeleteList.len) |i| bufToDeleteList[i] = .{};

        var texToDeleteLists: [rc.MAX_IN_FLIGHT + 1]FixedList(Texture, rc.TEX_MAX) = undefined;
        for (0..texToDeleteLists.len) |i| texToDeleteLists[i] = .{};

        return .{
            .vma = vma,
            .descMan = try DescriptorMan.init(vma, context.gpi, context.gpu),
            .stagingBuffers = stagingBuffers,
            .transfers = transfers,
            .bufToDeleteLists = bufToDeleteList,
            .texToDeleteLists = texToDeleteLists,
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        for (self.buffers.getElements()) |*buf| self.vma.freeBuffer(buf);
        for (self.textures.getElements()) |*tex| self.vma.freeTexture(tex);

        for (&self.bufToDeleteLists) |*bufList| {
            for (bufList.slice()) |*buf| self.vma.freeBuffer(buf);
        }
        for (&self.texToDeleteLists) |*texList| {
            for (texList.slice()) |*tex| self.vma.freeTexture(tex);
        }

        for (&self.stagingBuffers) |*stagingBuffer| self.vma.freeRawBuffer(stagingBuffer.handle, stagingBuffer.allocation);
        for (&self.transfers) |*transferList| transferList.deinit();

        self.descMan.deinit(self.vma);
        self.vma.deinit();
    }

    pub fn getBufferResourceSlot(self: *ResourceMan, bufId: Buffer.BufId, flightId: u8) !u32 {
        const buf = try self.getBufferPtr(bufId);
        const updateFlightId = if (buf.typ == .Indirect) flightId else buf.updateId;
        return buf.descIndices[updateFlightId];
    }

    pub fn getTextureResourceSlot(self: *ResourceMan, texId: Texture.TexId, flightId: u8) !u32 {
        const tex = try self.getTexturePtr(texId);
        return tex.descIndices[flightId];
    }

    pub fn resetTransfers(self: *ResourceMan, flightId: u8) void {
        self.stagingOffsets[flightId] = 0;
        self.transfers[flightId].clearRetainingCapacity();
    }

    pub fn getTexturePtr(self: *ResourceMan, texId: Texture.TexId) !*Texture {
        if (self.textures.isKeyUsed(texId.val) == true) return self.textures.getPtr(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn getBufferPtr(self: *ResourceMan, bufId: Buffer.BufId) !*Buffer {
        if (self.buffers.isKeyUsed(bufId.val) == true) return self.buffers.getPtr(bufId.val) else return error.BufferIdNotUsed;
    }

    pub fn createBuffer(self: *ResourceMan, bufInf: Buffer.BufInf) !void {
        var buffer = try self.vma.allocDefinedBuffer(bufInf);

        switch (bufInf.update) {
            .Overwrite => {
                const descIndex = try self.descMan.getFreeDescriptorIndex();

                try self.descMan.setBufferDescriptor(buffer.bases[0].gpuAddress, buffer.bases[0].size, descIndex, buffer.typ);
                for (0..buffer.descIndices.len) |i| buffer.descIndices[i] = descIndex;
            },
            .PerFrame => {
                for (0..buffer.descIndices.len) |i| {
                    const descIndex = try self.descMan.getFreeDescriptorIndex();

                    try self.descMan.setBufferDescriptor(buffer.bases[i].gpuAddress, buffer.bases[i].size, descIndex, buffer.typ);
                    buffer.descIndices[i] = descIndex;
                }
            },
        }
        std.debug.print("Buffer ID {}, Type {}, Update {} created! Descriptor Indices ", .{ bufInf.id.val, bufInf.typ, bufInf.update });
        for (buffer.descIndices) |index| std.debug.print("{} ", .{index});
        self.vma.printMemoryInfo(buffer.bases[0].allocation);

        self.buffers.set(bufInf.id.val, buffer);
    }

    pub fn createTexture(self: *ResourceMan, texInf: Texture.TexInf) !void {
        var tex = try self.vma.allocTexture(texInf);

        switch (texInf.update) {
            .Overwrite => {
                const descIndex = try self.descMan.getFreeDescriptorIndex();
                for (0..tex.descIndices.len) |i| tex.descIndices[i] = descIndex;

                switch (texInf.typ) {
                    .Color => try self.descMan.setTextureDescriptor(&tex.base[0], descIndex, .StorageTex),
                    .Depth, .Stencil => try self.descMan.setTextureDescriptor(&tex.base[0], descIndex, .SampledTex),
                }
            },
            .PerFrame => {
                for (0..tex.descIndices.len) |i| {
                    const descIndex = try self.descMan.getFreeDescriptorIndex();
                    tex.descIndices[i] = descIndex;

                    switch (texInf.typ) {
                        .Color => try self.descMan.setTextureDescriptor(&tex.base[i], descIndex, .StorageTex),
                        .Depth, .Stencil => try self.descMan.setTextureDescriptor(&tex.base[i], descIndex, .SampledTex),
                    }
                }
            },
        }
        std.debug.print("Texture ID {}, Type {}, Update {} created! Descriptor Indices ", .{ texInf.id.val, texInf.typ, texInf.update });
        for (tex.descIndices) |index| std.debug.print("{} ", .{index});
        self.vma.printMemoryInfo(tex.base[0].allocation);

        self.textures.set(texInf.id.val, tex);
    }

    pub fn getBufferDataPtr(self: *ResourceMan, bufId: Buffer.BufId, comptime T: type) !*T {
        const buffer = try self.getBufferPtr(bufId);
        if (buffer.bases[0].mappedPtr) |ptr| {
            return @as(*T, @ptrCast(@alignCast(ptr)));
        }
        return error.BufferNotHostVisible;
    }

    pub fn printReadbackBuffer(self: *ResourceMan, bufId: Buffer.BufId, comptime T: type) !void {
        const readbackPtr = try self.getBufferDataPtr(bufId, T);
        std.debug.print("Readback: {}\n", .{readbackPtr.*});
    }

    pub fn updateBuffer(self: *ResourceMan, bufInf: Buffer.BufInf, data: anytype, flightId: u8) !void {
        const DataType = @TypeOf(data);
        const bytes: []const u8 = switch (@typeInfo(DataType)) {
            .pointer => |ptr| switch (ptr.size) {
                .one => std.mem.asBytes(data),
                .slice => std.mem.sliceAsBytes(data),
                else => return error.UnsupportedPointerType,
            },
            else => return error.ExpectedPointer,
        };

        var buffer = try self.getBufferPtr(bufInf.id);
        if (bytes.len > buffer.bases[flightId].size) return error.BufferBaseTooSmallForUpdate;

        switch (bufInf.mem) {
            .Gpu => {
                const stagingOffset = self.stagingOffsets[flightId];
                if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

                try self.transfers[flightId].append(Transfer{ .srcOffset = stagingOffset, .dstResId = bufInf.id, .dstOffset = 0, .size = bytes.len });
                self.stagingOffsets[flightId] += (bytes.len + 15) & ~@as(u64, 15);

                const stagingPtr: [*]u8 = @ptrCast(self.stagingBuffers[flightId].mappedPtr);
                @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);
            },
            .CpuWrite => {
                const pMappedData = buffer.bases[flightId].mappedPtr orelse return error.BufferNotMapped;
                const destPtr: [*]u8 = @ptrCast(pMappedData);
                @memcpy(destPtr[0..bytes.len], bytes);
            },
            .CpuRead => return error.CpuReadBufferCantUpdate,
        }
        try self.descMan.setBufferDescriptor(buffer.bases[flightId].gpuAddress, bytes.len, buffer.descIndices[flightId], buffer.typ);
        buffer.bases[flightId].curCount = @intCast(bytes.len / bufInf.elementSize);
        buffer.updateId = flightId;
    }

    pub fn queueTextureDestruction(self: *ResourceMan, texId: Texture.TexId, curFrame: u64) !void {
        const tex = try self.getTexturePtr(texId);
        try self.texToDeleteLists[curFrame % rc.MAX_IN_FLIGHT + 1].append(tex.*);
        self.textures.removeAtKey(texId.val);
    }

    pub fn queueBufferDestruction(self: *ResourceMan, bufId: Buffer.BufId, curFrame: u64) !void {
        const buf = try self.getBufferPtr(bufId);
        try self.bufToDeleteLists[curFrame % rc.MAX_IN_FLIGHT + 1].append(buf.*);
        self.buffers.removeAtKey(bufId.val);
    }

    pub fn cleanupResources(self: *ResourceMan, curFrame: u64) !void {
        if (curFrame < rc.MAX_IN_FLIGHT) return; // Only clean up resources queued MAX_IN_FLIGHT ago (safety check for startup)

        const targetFrame = curFrame - rc.MAX_IN_FLIGHT;
        const queueIndex = targetFrame % rc.MAX_IN_FLIGHT + 1;

        if (self.texToDeleteLists[queueIndex].len > 0) {
            for (self.texToDeleteLists[queueIndex].slice()) |*tex| try self.destroyTexture(tex);
            self.texToDeleteLists[queueIndex].clear();
            std.debug.print("Textures destroyed: Frame {} (queued Frame {})\n", .{ curFrame, targetFrame });
        }

        if (self.bufToDeleteLists[queueIndex].len > 0) {
            for (self.bufToDeleteLists[queueIndex].slice()) |*buf| try self.destroyBuffer(buf);
            self.bufToDeleteLists[queueIndex].clear();
            std.debug.print("Buffers destroyed: Frame {} (queued Frame {})\n", .{ curFrame, targetFrame });
        }
    }

    fn destroyTexture(self: *ResourceMan, tex: *Texture) !void {
        self.vma.freeTexture(tex);

        const count = switch (tex.update) {
            .Overwrite => 1,
            .PerFrame => rc.MAX_IN_FLIGHT,
        };
        for (0..count) |i| try self.descMan.freeDescriptor(tex.descIndices[i]);
    }

    fn destroyBuffer(self: *ResourceMan, buf: *Buffer) !void {
        self.vma.freeBuffer(buf);

        const count = switch (buf.update) {
            .Overwrite => 1,
            .PerFrame => rc.MAX_IN_FLIGHT,
        };
        for (0..count) |i| try self.descMan.freeDescriptor(buf.descIndices[i]);
    }
};
