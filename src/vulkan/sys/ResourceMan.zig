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

    pub fn getBufferDescriptor(self: *ResourceMan, bufId: BufferMeta.BufId, flightId: u8) !u32 {
        const buffer = try self.getBuf(bufId, flightId);
        return buffer.descIndex;
    }

    pub fn getTextureDescriptor(self: *ResourceMan, texId: TextureMeta.TexId, flightId: u8) !u32 {
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
                var buf = try self.vma.allocDefinedBuffer(bufInf);
                buf.descIndex = try self.descMan.getFreeDescriptorIndex();
                try self.descMan.queueBufferDescriptor(buf.gpuAddress, buf.size, buf.descIndex, bufInf.typ);

                std.debug.print("Buffer ID {} created! (FlightId {}) ({}) ({}) (Descriptor {}) ", .{ bufInf.id.val, 0, bufInf.typ, bufInf.update, buf.descIndex });
                self.vma.printMemoryInfo(buf.allocation);

                self.resStorages[0].addBuf(bufInf.id, buf);
            },
            .PerFrame => {
                for (0..rc.MAX_IN_FLIGHT) |i| {
                    var buf = try self.vma.allocDefinedBuffer(bufInf);
                    buf.descIndex = try self.descMan.getFreeDescriptorIndex();
                    try self.descMan.queueBufferDescriptor(buf.gpuAddress, buf.size, buf.descIndex, bufInf.typ);

                    std.debug.print("Buffer ID {} created! (FlightId {}) ({}) ({}) (Descriptor {}) ", .{ bufInf.id.val, i, bufInf.typ, bufInf.update, buf.descIndex });
                    self.vma.printMemoryInfo(buf.allocation);

                    self.resStorages[i].addBuf(bufInf.id, buf);
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
                tex.descIndex = try self.descMan.getFreeDescriptorIndex();
                try self.descMan.queueTextureDescriptor(&texMeta, tex.img, tex.descIndex);

                std.debug.print("Texture ID {} created! (FlightId {}) ({}) ({}) (Descriptor {}) ", .{ texInf.id.val, 0, texInf.typ, texInf.update, tex.descIndex });
                self.vma.printMemoryInfo(tex.allocation);

                self.resStorages[0].addTex(texInf.id, tex);
            },
            .PerFrame => {
                for (0..rc.MAX_IN_FLIGHT) |i| {
                    var tex = try self.vma.allocDefinedTexture(texInf);
                    tex.descIndex = try self.descMan.getFreeDescriptorIndex();
                    try self.descMan.queueTextureDescriptor(&texMeta, tex.img, tex.descIndex);

                    std.debug.print("Texture ID {} created! (FlightId {}) ({}) ({}) (Descriptor {}) ", .{ texInf.id.val, i, texInf.typ, texInf.update, tex.descIndex });
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
        const bytes = try convertToByteSlice(data);
        const bufMeta = try self.getBufMeta(bufInf.id);

        const realFlightId = switch (bufMeta.update) {
            .Overwrite => 0,
            .PerFrame => flightId,
        };

        var targetStorage = &self.resStorages[realFlightId];
        const buf = try targetStorage.getBuf(bufInf.id);
        if (bytes.len > buf.size) return error.BufferBaseTooSmallForUpdate;

        switch (bufInf.mem) {
            .Gpu => {
                var resStorage = &self.resStorages[flightId];
                try resStorage.stageBufferUpdate(bufInf.id, bytes);
            },
            .CpuWrite => {
                const pMappedData = buf.mappedPtr orelse return error.BufferNotMapped;
                const destPtr: [*]u8 = @ptrCast(pMappedData);
                @memcpy(destPtr[0..bytes.len], bytes);
            },
            .CpuRead => return error.CpuReadBufferCantUpdate,
        }
        const newCount: u32 = @intCast(bytes.len / bufInf.elementSize);

        if (buf.curCount != newCount) {
            try self.descMan.queueBufferDescriptor(buf.gpuAddress, bytes.len, buf.descIndex, bufMeta.typ);
            buf.curCount = @intCast(bytes.len / bufInf.elementSize);
        }
        if (bufMeta.update == .PerFrame) bufMeta.updateId = flightId;
    }

    pub fn queueTextureDestruction(self: *ResourceMan, texId: TextureMeta.TexId) !void {
        const texMeta = try self.getTexMeta(texId);

        for (0..texMeta.update.getCount()) |i| {
            try self.resStorages[i].queueTexDestruction(texId);
        }
        self.texMetas.removeAtKey(texId.val);
    }

    pub fn queueBufferDestruction(self: *ResourceMan, bufId: BufferMeta.BufId) !void {
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
            std.debug.print("Buffers destroyed ({}) (in Frame {}) (FlightId {})\n", .{ bufZombies.len, curFrame, flightIndex });
        }
        resStorage.clearBufZombies();

        const texZombies = resStorage.getTexZombies();
        if (texZombies.len > 0) {
            for (texZombies) |*texZombie| self.destroyTexture(texZombie);
            std.debug.print("Textures destroyed ({}) (in Frame {}) (FlightId {})\n", .{ texZombies.len, curFrame, flightIndex });
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

fn convertToByteSlice(data: anytype) ![]const u8 {
    const DataType = @TypeOf(data);
    return switch (@typeInfo(DataType)) {
        .pointer => |ptr| switch (ptr.size) {
            .one => std.mem.asBytes(data),
            .slice => std.mem.sliceAsBytes(data),
            else => return error.UnsupportedPointerType,
        },
        else => return error.ExpectedPointer,
    };
}
