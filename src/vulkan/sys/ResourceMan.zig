const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const TextureBase = @import("../types/res/TextureBase.zig").TextureBase;
const ResourceStorage = @import("ResourceStorage.zig").ResourceStorage;
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

pub const BufferZombie = struct {
    descIndex: u32,
    bufBase: BufferBase,
};

pub const TextureZombie = struct {
    descIndex: u32,
    texBase: TextureBase,
};

pub const ResourceMan = struct {
    vma: Vma,
    alloc: Allocator,
    descMan: DescriptorMan,

    bufMetas: CreateMapArray(BufferMeta, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    texMetas: CreateMapArray(TextureMeta, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    bufLists: [rc.MAX_IN_FLIGHT]CreateMapArray(BufferBase, rc.BUF_MAX, u32, rc.BUF_MAX, 0),
    texLists: [rc.MAX_IN_FLIGHT]CreateMapArray(TextureBase, rc.TEX_MAX, u32, rc.TEX_MAX, 0),

    bufZombieLists: [rc.MAX_IN_FLIGHT + 1]FixedList(BufferZombie, rc.BUF_MAX),
    texZombieLists: [rc.MAX_IN_FLIGHT + 1]FixedList(TextureZombie, rc.TEX_MAX),

    resStorages: [rc.MAX_IN_FLIGHT]ResourceStorage,

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const vma = try Vma.init(context.instance, context.gpi, context.gpu);

        var resStorages: [rc.MAX_IN_FLIGHT]ResourceStorage = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| resStorages[i] = try ResourceStorage.init(alloc, &vma);

        var bufLists: [rc.MAX_IN_FLIGHT]CreateMapArray(BufferBase, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = undefined;
        for (0..bufLists.len) |i| bufLists[i] = .{};

        var texLists: [rc.MAX_IN_FLIGHT]CreateMapArray(TextureBase, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = undefined;
        for (0..texLists.len) |i| texLists[i] = .{};

        var bufZombieLists: [rc.MAX_IN_FLIGHT + 1]FixedList(BufferZombie, rc.BUF_MAX) = undefined;
        for (0..bufZombieLists.len) |i| bufZombieLists[i] = .{};

        var texZombieLists: [rc.MAX_IN_FLIGHT + 1]FixedList(TextureZombie, rc.TEX_MAX) = undefined;
        for (0..texZombieLists.len) |i| texZombieLists[i] = .{};

        return .{
            .vma = vma,
            .alloc = alloc,
            .descMan = try DescriptorMan.init(vma, context.gpi, context.gpu),
            .resStorages = resStorages,

            .bufLists = bufLists,
            .texLists = texLists,
            .bufZombieLists = bufZombieLists,
            .texZombieLists = texZombieLists,
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        for (0..self.bufLists.len) |i| {
            for (self.bufLists[i].getElements()) |*bufBase| {
                self.vma.freeBufferBase(bufBase);
            }
        }

        for (0..self.bufZombieLists.len) |i| {
            for (self.bufZombieLists[i].constSlice()) |*bufZombie| {
                self.vma.freeBufferBase(&bufZombie.bufBase);
            }
        }

        for (0..self.texLists.len) |i| {
            for (self.texLists[i].getElements()) |*texBase| {
                self.vma.freeTextureBase(texBase);
            }
        }

        for (0..self.texZombieLists.len) |i| {
            for (self.texZombieLists[i].constSlice()) |*texZombie| {
                self.vma.freeTextureBase(&texZombie.texBase);
            }
        }

        for (0..rc.MAX_IN_FLIGHT) |i| self.resStorages[i].deinit(&self.vma);
        self.descMan.deinit(&self.vma);
        self.vma.deinit();
    }

    pub fn update(self: *ResourceMan, flightId: u8, frame: u64) !void {
        if (rc.GPU_READBACK == true) try self.printReadbackBuffer(rc.readbackSB.id, vhT.ReadbackData, flightId);
        try self.cleanupResources(frame);
        try self.descMan.updateDescriptors();
    }

    pub fn getBufferResourceSlot(self: *ResourceMan, bufId: BufferMeta.BufId, flightId: u8) !u32 {
        const bufMeta = try self.getBufMeta(bufId);
        const updateFlightId = if (bufMeta.typ == .Indirect) flightId else bufMeta.updateId;
        return bufMeta.descIndices[updateFlightId];
    }

    pub fn getTextureResourceSlot(self: *ResourceMan, texId: TextureMeta.TexId, flightId: u8) !u32 {
        const texMeta = self.texMetas.getPtr(texId.val);
        return texMeta.descIndices[flightId];
    }

    pub fn resetTransfers(self: *ResourceMan, flightId: u8) void {
        self.resStorages[flightId].resetTransfers();
    }

    pub fn getTex(self: *ResourceMan, texId: TextureMeta.TexId, flightId: u8) !*TextureBase {
        if (self.texLists[flightId].isKeyUsed(texId.val) == true) return self.texLists[flightId].getPtr(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn getBuf(self: *ResourceMan, bufId: BufferMeta.BufId, flightId: u8) !*BufferBase {
        const bufMeta = try self.getBufMeta(bufId);
        const updateFlightId = if (bufMeta.typ == .Indirect) flightId else bufMeta.updateId;
        if (self.bufLists[updateFlightId].isKeyUsed(bufId.val) == true) return self.bufLists[updateFlightId].getPtr(bufId.val) else return error.BufferIdNotUsed;
    }

    pub fn getTexMeta(self: *ResourceMan, texId: TextureMeta.TexId) !*TextureMeta {
        if (self.texMetas.isKeyUsed(texId.val) == true) return self.texMetas.getPtr(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn getBufMeta(self: *ResourceMan, bufId: BufferMeta.BufId) !*BufferMeta {
        if (self.bufMetas.isKeyUsed(bufId.val) == true) return self.bufMetas.getPtr(bufId.val) else return error.BufferIdNotUsed;
    }

    pub fn createBuffer(self: *ResourceMan, bufInf: BufferMeta.BufInf) !void {
        var bufMeta: BufferMeta = self.vma.createBufferMeta(bufInf);

        switch (bufInf.update) {
            .Overwrite => {
                const buffer = try self.vma.allocDefinedBuffer(bufInf);
                const descIndex = try self.descMan.getFreeDescriptorIndex();
                try self.descMan.queueBufferDescriptor(buffer.gpuAddress, buffer.size, descIndex, bufInf.typ);

                for (0..rc.MAX_IN_FLIGHT) |i| {
                    bufMeta.descIndices[i] = descIndex;
                }
                self.bufLists[0].set(bufInf.id.val, buffer);

                std.debug.print("Buffer ID {} (in List {}), Type {}, Update {} created! Descriptor Indices ", .{ bufInf.id.val, 0, bufInf.typ, bufInf.update });
                for (bufMeta.descIndices) |index| std.debug.print("{} ", .{index});
                self.vma.printMemoryInfo(buffer.allocation);
            },
            .PerFrame => {
                for (0..rc.MAX_IN_FLIGHT) |i| {
                    const buffer = try self.vma.allocDefinedBuffer(bufInf);
                    const descIndex = try self.descMan.getFreeDescriptorIndex();
                    try self.descMan.queueBufferDescriptor(buffer.gpuAddress, buffer.size, descIndex, bufInf.typ);

                    bufMeta.descIndices[i] = descIndex;

                    self.bufLists[i].set(bufInf.id.val, buffer);

                    std.debug.print("Buffer ID {} (in List {}), Type {}, Update {} created! Descriptor Index {} ", .{ bufInf.id.val, i, bufInf.typ, bufInf.update, descIndex });
                    self.vma.printMemoryInfo(buffer.allocation);
                }
            },
        }
        self.bufMetas.set(bufInf.id.val, bufMeta);
    }

    pub fn createTexture(self: *ResourceMan, texInf: TextureMeta.TexInf) !void {
        var texMeta: TextureMeta = self.vma.createTextureMeta(texInf);

        switch (texInf.update) {
            .Overwrite => {
                const tex = try self.vma.allocDefinedTexture(texInf);
                const descIndex = try self.descMan.getFreeDescriptorIndex();
                try self.descMan.queueTextureDescriptor(&texMeta, tex.img, descIndex);

                for (0..rc.MAX_IN_FLIGHT) |i| {
                    texMeta.descIndices[i] = descIndex;
                }
                self.texLists[0].set(texInf.id.val, tex);

                std.debug.print("Texture ID {} (in List {}), Type {}, Update {} created! Descriptor Indices ", .{ texInf.id.val, 0, texInf.typ, texInf.update });
                for (texMeta.descIndices) |index| std.debug.print("{} ", .{index});
                self.vma.printMemoryInfo(tex.allocation);
            },
            .PerFrame => {
                for (0..rc.MAX_IN_FLIGHT) |i| {
                    const tex = try self.vma.allocDefinedTexture(texInf);
                    const descIndex = try self.descMan.getFreeDescriptorIndex();
                    try self.descMan.queueTextureDescriptor(&texMeta, tex.img, descIndex);

                    texMeta.descIndices[i] = descIndex;
                    self.texLists[i].set(texInf.id.val, tex);

                    std.debug.print("Buffer ID {} (in List {}), Type {}, Update {} created! Descriptor Index {}", .{ texInf.id.val, i, texInf.typ, texInf.update, descIndex });
                    self.vma.printMemoryInfo(tex.allocation);
                }
            },
        }
        self.texMetas.set(texInf.id.val, texMeta);
    }

    pub fn getBufferDataPtr(self: *ResourceMan, bufId: BufferMeta.BufId, comptime T: type, flightId: u8) !*T {
        const buffer = try self.getBuf(bufId);
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

        const bufMeta = try self.getBufMeta(bufInf.id);
        const realFlightId = switch (bufMeta.update) {
            .Overwrite => 0,
            .PerFrame => flightId,
        };

        const buffer = try self.getBuf(bufInf.id, realFlightId);

        if (bytes.len > buffer.size) return error.BufferBaseTooSmallForUpdate;

        var resStorage = &self.resStorages[flightId];

        switch (bufInf.mem) {
            .Gpu => {
                const stagingOffset = resStorage.stagingOffset;
                if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

                try resStorage.transfers.append(.{ .srcOffset = stagingOffset, .dstResId = bufInf.id, .dstOffset = 0, .size = bytes.len });
                resStorage.stagingOffset += (bytes.len + 15) & ~@as(u64, 15);

                const stagingPtr: [*]u8 = @ptrCast(resStorage.stagingBuffer.mappedPtr);
                @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);
            },
            .CpuWrite => {
                const pMappedData = buffer.mappedPtr orelse return error.BufferNotMapped;
                const destPtr: [*]u8 = @ptrCast(pMappedData);
                @memcpy(destPtr[0..bytes.len], bytes);
            },
            .CpuRead => return error.CpuReadBufferCantUpdate,
        }
        try self.descMan.queueBufferDescriptor(buffer.gpuAddress, bytes.len, bufMeta.descIndices[flightId], bufMeta.typ);
        buffer.curCount = @intCast(bytes.len / bufInf.elementSize);
        bufMeta.updateId = flightId;
    }

    pub fn queueTextureDestruction(self: *ResourceMan, texId: TextureMeta.TexId, curFrame: u64) !void {
        const texMeta = try self.getTexMeta(texId);

        for (0..texMeta.update.getCount()) |i| {
            const tex = try self.getTex(texId, @intCast(i));
            try self.texZombieLists[curFrame % rc.MAX_IN_FLIGHT + 1].append(TextureZombie{ .descIndex = texMeta.*.descIndices[i], .texBase = tex.* });
            self.texLists[i].removeAtKey(texId.val);
        }

        self.texMetas.removeAtKey(texId.val);
    }

    pub fn queueBufferDestruction(self: *ResourceMan, bufId: BufferMeta.BufId, curFrame: u64) !void {
        const bufMeta = try self.getBufMeta(bufId);

        for (0..bufMeta.update.getCount()) |i| {
            const buffer = try self.getBuf(bufId, @intCast(i));
            try self.bufZombieLists[curFrame % rc.MAX_IN_FLIGHT + 1].append(BufferZombie{ .descIndex = bufMeta.*.descIndices[i], .bufBase = buffer.* });
            self.bufLists[i].removeAtKey(bufId.val);
        }

        self.bufMetas.removeAtKey(bufId.val);
    }

    pub fn cleanupResources(self: *ResourceMan, curFrame: u64) !void {
        if (curFrame < rc.MAX_IN_FLIGHT) return; // Only clean up resources queued MAX_IN_FLIGHT ago (safety check for startup)

        const targetFrame = curFrame - rc.MAX_IN_FLIGHT;
        const queueIndex = targetFrame % rc.MAX_IN_FLIGHT + 1;

        if (self.texZombieLists[queueIndex].len > 0) {
            for (self.texZombieLists[queueIndex].constSlice()) |*texZombie| {
                self.destroyTexture(texZombie.*.descIndex, &texZombie.texBase);
            }
            self.texZombieLists[queueIndex].clear();
            std.debug.print("Textures destroyed: Frame {} (queued Frame {})\n", .{ curFrame, targetFrame });
        }

        if (self.bufZombieLists[queueIndex].len > 0) {
            for (self.bufZombieLists[queueIndex].constSlice()) |*bufZombie| {
                self.destroyBuffer(bufZombie.*.descIndex, &bufZombie.bufBase);
            }
            self.bufZombieLists[queueIndex].clear();
            std.debug.print("Buffers destroyed: Frame {} (queued Frame {})\n", .{ curFrame, targetFrame });
        }
    }

    fn destroyTexture(self: *ResourceMan, descIndex: u32, texBase: *const TextureBase) void {
        self.vma.freeTextureBase(texBase);
        self.descMan.freeDescriptor(descIndex);
    }

    fn destroyBuffer(self: *ResourceMan, descIndex: u32, bufBase: *const BufferBase) void {
        self.vma.freeBufferBase(bufBase);
        self.descMan.freeDescriptor(descIndex);
    }
};
