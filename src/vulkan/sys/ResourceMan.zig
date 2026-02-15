const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const TextureBase = @import("../types/res/TextureBase.zig").TextureBase;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const BufferBase = @import("../types/res/BufferBase.zig").BufferBase;
const DescriptorMan = @import("DescriptorMan.zig").DescriptorMan;
const PushData = @import("../types/res/PushData.zig").PushData;
const rc = @import("../../configs/renderConfig.zig");
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const vhT = @import("../help/Types.zig");
const vhE = @import("../help/Enums.zig");
const Allocator = std.mem.Allocator;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

pub const Transfer = struct {
    srcOffset: u64,
    dstResId: BufferMeta.BufId,
    dstOffset: u64,
    size: u64,
};

pub const BufferBundle = struct {
    bases: [rc.MAX_IN_FLIGHT]BufferBase,
};

pub const TextureBundle = struct {
    bases: [rc.MAX_IN_FLIGHT]TextureBase,
};

pub const ResourceMan = struct {
    vma: Vma,
    alloc: Allocator,
    descMan: DescriptorMan,

    bufMetas: CreateMapArray(BufferMeta, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    texMetas: CreateMapArray(TextureMeta, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    bufBundles: CreateMapArray(BufferBundle, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    texBundles: CreateMapArray(TextureBundle, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    realFramesInFlights: [rc.MAX_IN_FLIGHT]u64 = .{0} ** rc.MAX_IN_FLIGHT,

    bufToDeleteLists: [rc.MAX_IN_FLIGHT + 1]FixedList(u32, rc.BUF_MAX),
    texToDeleteLists: [rc.MAX_IN_FLIGHT + 1]FixedList(u32, rc.TEX_MAX),

    stagingBuffers: [rc.MAX_IN_FLIGHT]BufferBase,
    stagingOffsets: [rc.MAX_IN_FLIGHT]u64 = .{0} ** rc.MAX_IN_FLIGHT,
    transfers: [rc.MAX_IN_FLIGHT]std.array_list.Managed(Transfer),

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const vma = try Vma.init(context.instance, context.gpi, context.gpu);

        var stagingBuffers: [rc.MAX_IN_FLIGHT]BufferBase = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| stagingBuffers[i] = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE);

        var transfers: [rc.MAX_IN_FLIGHT]std.array_list.Managed(Transfer) = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| transfers[i] = std.array_list.Managed(Transfer).init(alloc);

        var bufToDeleteList: [rc.MAX_IN_FLIGHT + 1]FixedList(u32, rc.BUF_MAX) = undefined;
        for (0..bufToDeleteList.len) |i| bufToDeleteList[i] = .{};

        var texToDeleteLists: [rc.MAX_IN_FLIGHT + 1]FixedList(u32, rc.TEX_MAX) = undefined;
        for (0..texToDeleteLists.len) |i| texToDeleteLists[i] = .{};

        return .{
            .vma = vma,
            .alloc = alloc,
            .descMan = try DescriptorMan.init(vma, context.gpi, context.gpu),
            .stagingBuffers = stagingBuffers,
            .transfers = transfers,
            .bufToDeleteLists = bufToDeleteList,
            .texToDeleteLists = texToDeleteLists,
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        for (0..self.bufMetas.getCount()) |i| {
            const updateTyp = self.bufMetas.getAtIndex(@intCast(i)).update;
            const bufBundle = self.bufBundles.getPtrAtIndex(@intCast(i));
            self.vma.freeBuffer(bufBundle, updateTyp);
        }

        for (0..self.texBundles.getCount()) |i| {
            const updateTyp = self.texMetas.getAtIndex(@intCast(i)).update;
            const texBundle = self.texBundles.getPtrAtIndex(@intCast(i));
            self.vma.freeTexture(texBundle, updateTyp);
        }

        for (&self.stagingBuffers) |*stagingBuffer| self.vma.freeRawBuffer(stagingBuffer.handle, stagingBuffer.allocation);
        for (&self.transfers) |*transferList| transferList.deinit();

        self.descMan.deinit(self.vma);
        self.vma.deinit();
    }

    pub fn update(self: *ResourceMan, flightId: u8, frame: u64) !void {
        if (rc.GPU_READBACK == true) try self.printReadbackBuffer(rc.readbackSB.id, vhT.ReadbackData, flightId);
        try self.cleanupResources(frame);
        try self.descMan.updateDescriptors();
    }

    pub fn getBufferResourceSlot(self: *ResourceMan, bufId: BufferMeta.BufId, flightId: u8) !u32 {
        const bufMeta = try self.getBufferMeta(bufId);
        const updateFlightId = if (bufMeta.typ == .Indirect) flightId else bufMeta.updateId;
        return bufMeta.descIndices[updateFlightId];
    }

    pub fn getTextureResourceSlot(self: *ResourceMan, texId: TextureMeta.TexId, flightId: u8) !u32 {
        const texMeta = self.texMetas.getPtr(texId.val);
        return texMeta.descIndices[flightId];
    }

    pub fn resetTransfers(self: *ResourceMan, flightId: u8) void {
        self.stagingOffsets[flightId] = 0;
        self.transfers[flightId].clearRetainingCapacity();
    }

    pub fn getTexBundle(self: *ResourceMan, texId: TextureMeta.TexId) !*TextureBundle {
        if (self.texBundles.isKeyUsed(texId.val) == true) return self.texBundles.getPtr(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn getBufBundle(self: *ResourceMan, bufId: BufferMeta.BufId) !*BufferBundle {
        if (self.bufBundles.isKeyUsed(bufId.val) == true) return self.bufBundles.getPtr(bufId.val) else return error.BufferIdNotUsed;
    }

    pub fn getTextureMeta(self: *ResourceMan, texId: TextureMeta.TexId) !*TextureMeta {
        if (self.texMetas.isKeyUsed(texId.val) == true) return self.texMetas.getPtr(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn getBufferMeta(self: *ResourceMan, bufId: BufferMeta.BufId) !*BufferMeta {
        if (self.bufMetas.isKeyUsed(bufId.val) == true) return self.bufMetas.getPtr(bufId.val) else return error.BufferIdNotUsed;
    }

    pub fn createBuffer(self: *ResourceMan, bufInf: BufferMeta.BufInf) !void {
        var bufBundle: BufferBundle = undefined;
        var bufMeta: BufferMeta = self.vma.createBufferMeta(bufInf);

        switch (bufInf.update) {
            .Overwrite => {
                const buffer = try self.vma.allocDefinedBuffer(bufInf);
                const descIndex = try self.descMan.getFreeDescriptorIndex();
                try self.descMan.queueBufferDescriptor(buffer.gpuAddress, buffer.size, descIndex, bufInf.typ);

                for (0..rc.MAX_IN_FLIGHT) |i| {
                    bufMeta.descIndices[i] = descIndex;
                    bufBundle.bases[i] = buffer;
                }
            },
            .PerFrame => {
                for (0..rc.MAX_IN_FLIGHT) |i| {
                    const buffer = try self.vma.allocDefinedBuffer(bufInf);
                    const descIndex = try self.descMan.getFreeDescriptorIndex();
                    try self.descMan.queueBufferDescriptor(buffer.gpuAddress, buffer.size, descIndex, bufInf.typ);

                    bufMeta.descIndices[i] = descIndex;
                    bufBundle.bases[i] = buffer;
                }
            },
        }
        std.debug.print("Buffer ID {}, Type {}, Update {} created! Descriptor Indices ", .{ bufInf.id.val, bufInf.typ, bufInf.update });
        for (bufMeta.descIndices) |index| std.debug.print("{} ", .{index});
        self.vma.printMemoryInfo(bufBundle.bases[0].allocation);

        self.bufMetas.set(bufInf.id.val, bufMeta);
        self.bufBundles.set(bufInf.id.val, bufBundle);
    }

    pub fn createTexture(self: *ResourceMan, texInf: TextureMeta.TexInf) !void {
        var texBundle: TextureBundle = undefined;
        var texMeta: TextureMeta = self.vma.createTextureMeta(texInf);

        switch (texInf.update) {
            .Overwrite => {
                const tex = try self.vma.allocDefinedTexture(texInf);
                const descIndex = try self.descMan.getFreeDescriptorIndex();
                try self.descMan.queueTextureDescriptor(&texMeta, tex.img, descIndex);

                for (0..rc.MAX_IN_FLIGHT) |i| {
                    texMeta.descIndices[i] = descIndex;
                    texBundle.bases[i] = tex;
                }
            },
            .PerFrame => {
                for (0..rc.MAX_IN_FLIGHT) |i| {
                    const tex = try self.vma.allocDefinedTexture(texInf);
                    const descIndex = try self.descMan.getFreeDescriptorIndex();
                    try self.descMan.queueTextureDescriptor(&texMeta, tex.img, descIndex);

                    texMeta.descIndices[i] = descIndex;
                    texBundle.bases[i] = tex;
                }
            },
        }
        std.debug.print("Texture ID {}, Type {}, Update {} created! Descriptor Indices ", .{ texInf.id.val, texInf.typ, texInf.update });
        for (texMeta.descIndices) |index| std.debug.print("{} ", .{index});
        self.vma.printMemoryInfo(texBundle.bases[0].allocation);

        self.texMetas.set(texInf.id.val, texMeta);
        self.texBundles.set(texInf.id.val, texBundle);
    }

    pub fn getBufferDataPtr(self: *ResourceMan, bufId: BufferMeta.BufId, comptime T: type, flightId: u8) !*T {
        const buffer = try self.getBufBundle(bufId);
        if (buffer.bases[flightId].mappedPtr) |ptr| {
            return @as(*T, @ptrCast(@alignCast(ptr)));
        }
        return error.BufferNotHostVisible;
    }

    pub fn printReadbackBuffer(self: *ResourceMan, bufId: BufferMeta.BufId, comptime T: type, flightId: u8) !void {
        const readbackPtr = try self.getBufferDataPtr(bufId, T, flightId);
        std.debug.print("Readback: {}\n", .{readbackPtr.*});
    }

    pub fn updateBuffer(self: *ResourceMan, bufInf: BufferMeta.BufInf, data: anytype, flightId: u8) !void {
        const DataType = @TypeOf(data);
        const bytes: []const u8 = switch (@typeInfo(DataType)) {
            .pointer => |ptr| switch (ptr.size) {
                .one => std.mem.asBytes(data),
                .slice => std.mem.sliceAsBytes(data),
                else => return error.UnsupportedPointerType,
            },
            else => return error.ExpectedPointer,
        };

        const bufBundle = try self.getBufBundle(bufInf.id);
        const bufMeta = try self.getBufferMeta(bufInf.id);

        if (bytes.len > bufBundle.bases[flightId].size) return error.BufferBaseTooSmallForUpdate;

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
                const pMappedData = bufBundle.bases[flightId].mappedPtr orelse return error.BufferNotMapped;
                const destPtr: [*]u8 = @ptrCast(pMappedData);
                @memcpy(destPtr[0..bytes.len], bytes);
            },
            .CpuRead => return error.CpuReadBufferCantUpdate,
        }
        try self.descMan.queueBufferDescriptor(bufBundle.bases[flightId].gpuAddress, bytes.len, bufMeta.descIndices[flightId], bufMeta.typ);
        bufBundle.bases[flightId].curCount = @intCast(bytes.len / bufInf.elementSize);
        bufMeta.updateId = flightId;
    }

    pub fn queueTextureDestruction(self: *ResourceMan, texId: TextureMeta.TexId, curFrame: u64) !void {
        const metaIdx = self.texMetas.getIndex(texId.val);
        try self.texToDeleteLists[curFrame % rc.MAX_IN_FLIGHT + 1].append(metaIdx);

        self.texMetas.unlink(texId.val);
        self.texBundles.unlink(texId.val);
    }

    pub fn queueBufferDestruction(self: *ResourceMan, bufId: BufferMeta.BufId, curFrame: u64) !void {
        const metaIdx = self.bufMetas.getIndex(bufId.val);
        try self.bufToDeleteLists[curFrame % rc.MAX_IN_FLIGHT + 1].append(metaIdx);

        self.bufMetas.unlink(bufId.val);
        self.bufBundles.unlink(bufId.val);
    }

    pub fn cleanupResources(self: *ResourceMan, curFrame: u64) !void {
        if (curFrame < rc.MAX_IN_FLIGHT) return; // Only clean up resources queued MAX_IN_FLIGHT ago (safety check for startup)

        const targetFrame = curFrame - rc.MAX_IN_FLIGHT;
        const queueIndex = targetFrame % rc.MAX_IN_FLIGHT + 1;

        if (self.texToDeleteLists[queueIndex].len > 0) {
            for (self.texToDeleteLists[queueIndex].slice()) |texIndex| {
                try self.destroyTexture(texIndex);
                self.texMetas.removeAtIndex(texIndex);
                self.texBundles.removeAtIndex(texIndex);
            }
            self.texToDeleteLists[queueIndex].clear();
            std.debug.print("Textures destroyed: Frame {} (queued Frame {})\n", .{ curFrame, targetFrame });
        }

        if (self.bufToDeleteLists[queueIndex].len > 0) {
            for (self.bufToDeleteLists[queueIndex].slice()) |bufIndex| {
                try self.destroyBuffer(bufIndex);
                self.bufMetas.removeAtIndex(bufIndex);
                self.bufBundles.removeAtIndex(bufIndex);
            }
            self.bufToDeleteLists[queueIndex].clear();
            std.debug.print("Buffers destroyed: Frame {} (queued Frame {})\n", .{ curFrame, targetFrame });
        }
    }

    pub fn destroyTexture(self: *ResourceMan, texIndex: u32) !void {
        const texMeta = self.texMetas.getPtrAtIndex(texIndex);
        const texBundle = self.texBundles.getPtrAtIndex(texIndex);

        self.vma.freeTexture(texBundle, texMeta.update);

        const count = switch (texMeta.update) {
            .Overwrite => 1,
            .PerFrame => rc.MAX_IN_FLIGHT,
        };
        for (0..count) |i| try self.descMan.freeDescriptor(texMeta.descIndices[i]);
    }

    pub fn destroyBuffer(self: *ResourceMan, bufIndex: u32) !void {
        const bufMeta = self.bufMetas.getPtrAtIndex(bufIndex);
        const bufBundle = self.bufBundles.getPtrAtIndex(bufIndex);

        self.vma.freeBuffer(bufBundle, bufMeta.update);

        const count = switch (bufMeta.update) {
            .Overwrite => 1,
            .PerFrame => rc.MAX_IN_FLIGHT,
        };
        for (0..count) |i| try self.descMan.freeDescriptor(bufMeta.descIndices[i]);
    }
};
