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

pub const ResourceMan = struct {
    vma: Vma,
    alloc: Allocator,
    descMan: DescriptorMan,

    resStorages: [rc.MAX_IN_FLIGHT]ResourceStorage,

    bufMetas: CreateMapArray(BufferMeta, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    texMetas: CreateMapArray(TextureMeta, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const vma = try Vma.init(context.instance, context.gpi, context.gpu);

        var resStorages: [rc.MAX_IN_FLIGHT]ResourceStorage = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| resStorages[i] = try ResourceStorage.init(alloc, &vma);

        return .{
            .vma = vma,
            .alloc = alloc,
            .descMan = try DescriptorMan.init(vma, context.gpi, context.gpu),
            .resStorages = resStorages,
        };
    }

    pub fn deinit(self: *ResourceMan) void {
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
        const buffer = try self.getBuf(bufId, flightId);
        return buffer.descIndex;
    }

    pub fn getTextureResourceSlot(self: *ResourceMan, texId: TextureMeta.TexId, flightId: u8) !u32 {
        const tex = try self.getTex(texId, flightId);
        return tex.descIndex;
    }

    pub fn resetTransfers(self: *ResourceMan, flightId: u8) void {
        self.resStorages[flightId].resetTransfers();
    }

    pub fn getTex(self: *ResourceMan, texId: TextureMeta.TexId, flightId: u8) !*TextureBase {
        const texMeta = try self.getTexMeta(texId);
        const realIndex = switch (texMeta.update) {
            .Overwrite => 0,
            .PerFrame => flightId,
        };
        return try self.resStorages[realIndex].getTex(texId);
    }

    pub fn getBuf(self: *ResourceMan, bufId: BufferMeta.BufId, flightId: u8) !*BufferBase {
        const bufMeta = try self.getBufMeta(bufId);
        const realIndex = switch (bufMeta.update) {
            .Overwrite => 0,
            .PerFrame => if (bufMeta.typ == .Indirect) flightId else bufMeta.updateId,
        };
        return try self.resStorages[realIndex].getBuf(bufId);
    }

    pub fn getTexMeta(self: *ResourceMan, texId: TextureMeta.TexId) !*TextureMeta {
        if (self.texMetas.isKeyUsed(texId.val) == true) return self.texMetas.getPtr(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn getBufMeta(self: *ResourceMan, bufId: BufferMeta.BufId) !*BufferMeta {
        if (self.bufMetas.isKeyUsed(bufId.val) == true) return self.bufMetas.getPtr(bufId.val) else return error.BufferIdNotUsed;
    }

    pub fn createBuffer(self: *ResourceMan, bufInf: BufferMeta.BufInf) !void {
        switch (bufInf.update) {
            .Overwrite => {
                var buffer = try self.vma.allocDefinedBuffer(bufInf);
                const descIndex = try self.descMan.getFreeDescriptorIndex();
                buffer.descIndex = descIndex;
                try self.descMan.queueBufferDescriptor(buffer.gpuAddress, buffer.size, descIndex, bufInf.typ);

                std.debug.print("Buffer ID {} (in List {}), Type {}, Update {} created! Descriptor Index {} ", .{ bufInf.id.val, 0, bufInf.typ, bufInf.update, descIndex });
                self.vma.printMemoryInfo(buffer.allocation);

                self.resStorages[0].addBuf(bufInf.id, buffer);
            },
            .PerFrame => {
                for (0..rc.MAX_IN_FLIGHT) |i| {
                    var buffer = try self.vma.allocDefinedBuffer(bufInf);
                    const descIndex = try self.descMan.getFreeDescriptorIndex();
                    buffer.descIndex = descIndex;
                    try self.descMan.queueBufferDescriptor(buffer.gpuAddress, buffer.size, descIndex, bufInf.typ);

                    std.debug.print("Buffer ID {} (in List {}), Type {}, Update {} created! Descriptor Index {} ", .{ bufInf.id.val, i, bufInf.typ, bufInf.update, descIndex });
                    self.vma.printMemoryInfo(buffer.allocation);

                    self.resStorages[i].addBuf(bufInf.id, buffer);
                }
            },
        }
        self.bufMetas.set(bufInf.id.val, self.vma.createBufferMeta(bufInf));
    }

    pub fn createTexture(self: *ResourceMan, texInf: TextureMeta.TexInf) !void {
        var texMeta: TextureMeta = self.vma.createTextureMeta(texInf);

        switch (texInf.update) {
            .Overwrite => {
                var tex = try self.vma.allocDefinedTexture(texInf);
                const descIndex = try self.descMan.getFreeDescriptorIndex();
                tex.descIndex = descIndex;
                try self.descMan.queueTextureDescriptor(&texMeta, tex.img, descIndex);

                std.debug.print("Texture ID {} (in List {}), Type {}, Update {} created! Descriptor Index {} ", .{ texInf.id.val, 0, texInf.typ, texInf.update, descIndex });
                self.vma.printMemoryInfo(tex.allocation);

                self.resStorages[0].addTex(texInf.id, tex);
            },
            .PerFrame => {
                for (0..rc.MAX_IN_FLIGHT) |i| {
                    var tex = try self.vma.allocDefinedTexture(texInf);
                    const descIndex = try self.descMan.getFreeDescriptorIndex();
                    tex.descIndex = descIndex;
                    try self.descMan.queueTextureDescriptor(&texMeta, tex.img, descIndex);

                    std.debug.print("Buffer ID {} (in List {}), Type {}, Update {} created! Descriptor Index {} ", .{ texInf.id.val, i, texInf.typ, texInf.update, descIndex });
                    self.vma.printMemoryInfo(tex.allocation);

                    self.resStorages[i].addTex(texInf.id, tex);
                }
            },
        }
        self.texMetas.set(texInf.id.val, texMeta);
    }

    pub fn getBufferDataPtr(self: *ResourceMan, bufId: BufferMeta.BufId, comptime T: type, flightId: u8) !*T {
        const buffer = try self.getBuf(bufId, flightId);

        if (buffer.mappedPtr) |ptr| {
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
        try self.descMan.queueBufferDescriptor(buffer.gpuAddress, bytes.len, buffer.descIndex, bufMeta.typ);
        buffer.curCount = @intCast(bytes.len / bufInf.elementSize);

        if (bufMeta.update == .PerFrame) {
            bufMeta.updateId = flightId;
        }
    }

    pub fn queueTextureDestruction(self: *ResourceMan, texId: TextureMeta.TexId, _: u64) !void {
        const texMeta = try self.getTexMeta(texId);

        for (0..texMeta.update.getCount()) |i| {
            try self.resStorages[i].queueTexDestruction(texId);
        }
        self.texMetas.removeAtKey(texId.val);
    }

    pub fn queueBufferDestruction(self: *ResourceMan, bufId: BufferMeta.BufId, _: u64) !void {
        const bufMeta = try self.getBufMeta(bufId);

        for (0..bufMeta.update.getCount()) |i| {
            try self.resStorages[i].queueBufDestruction(bufId);
        }
        self.bufMetas.removeAtKey(bufId.val);
    }

    pub fn cleanupResources(self: *ResourceMan, curFrame: u64) !void {
        if (curFrame < rc.MAX_IN_FLIGHT) return; // Only clean up resources queued MAX_IN_FLIGHT ago (safety check for startup)

        const targetFrame = curFrame - rc.MAX_IN_FLIGHT;
        const flightIndex = targetFrame % rc.MAX_IN_FLIGHT;
        const resStorage = &self.resStorages[flightIndex];

        const bufZombies = resStorage.getBufZombies();
        if (bufZombies.len > 0) {
            for (bufZombies) |*bufZombie| self.destroyBuffer(bufZombie);
            std.debug.print("Buffers destroyed (Count {}) (Frame {}) (queued Frame {})\n", .{ bufZombies.len, curFrame, targetFrame });
        }
        resStorage.clearBufZombies();

        const texZombies = resStorage.getTexZombies();
        if (texZombies.len > 0) {
            for (texZombies) |*texZombie| self.destroyTexture(texZombie);
            std.debug.print("Textures destroyed (Count {}) (Frame {}) (queued Frame {})\n", .{ texZombies.len, curFrame, targetFrame });
        }
        resStorage.clearTexZombies();
    }

    fn destroyTexture(self: *ResourceMan, texBase: *const TextureBase) void {
        self.vma.freeTextureBase(texBase);
        self.descMan.freeDescriptor(texBase.descIndex);
    }

    fn destroyBuffer(self: *ResourceMan, bufBase: *const BufferBase) void {
        self.vma.freeBufferBase(bufBase);
        self.descMan.freeDescriptor(bufBase.descIndex);
    }
};
