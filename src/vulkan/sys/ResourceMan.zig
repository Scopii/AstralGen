// const DescriptorStorage = @import("DescriptorStorage.zig").DescriptorStorage;
const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const ResourceStorage = @import("ResourceStorage.zig").ResourceStorage;
const DescriptorMan = @import("DescriptorMan.zig").DescriptorMan;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../structures/LinkedMap.zig").LinkedMap;
const ArrayList = @import("../../structures/ArrayList.zig").ArrayList;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const PushData = @import("../types/res/PushData.zig").PushData;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
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

    resStorages: [rc.MAX_IN_FLIGHT]ResourceStorage,
    descMan: DescriptorMan,
    bufMetas: LinkedMap(BufferMeta, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    texMetas: LinkedMap(TextureMeta, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const vma = try Vma.init(context.instance, context.gpi, context.gpu);

        var resStorages: [rc.MAX_IN_FLIGHT]ResourceStorage = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| {
            resStorages[i] = try ResourceStorage.init(alloc, &vma);
        }

        return .{
            .vma = vma,
            .alloc = alloc,
            .resStorages = resStorages,
            .descMan = try DescriptorMan.init(&vma, context.gpu),
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        for (0..rc.MAX_IN_FLIGHT) |i| self.resStorages[i].deinit(&self.vma);
        self.descMan.deinit(&self.vma);
        self.vma.deinit();
    }

    fn getBufferDataPtr(self: *ResourceMan, bufId: BufferMeta.BufId, comptime T: type, flightId: u8) !*T {
        const buffer = try self.getBuffer(bufId, flightId);
        if (buffer.mappedPtr) |ptr| {
            return @as(*T, @ptrCast(@alignCast(ptr)));
        }
        return error.BufferNotHostVisible;
    }

    fn printReadbackBuffer(self: *ResourceMan, bufId: BufferMeta.BufId, comptime T: type, flightId: u8) !void {
        const readbackPtr = try self.getBufferDataPtr(bufId, T, flightId);
        std.debug.print("Readback: {}\n", .{readbackPtr.*});
    }

    pub fn update(self: *ResourceMan, flightId: u8, curFrame: u64) !void {
        if (rc.GPU_READBACK == true) try self.printReadbackBuffer(rc.readbackSB.id, vhT.ReadbackData, flightId);

        try self.descMan.updateDescriptors(self.vma.gpi, flightId);

        if (curFrame < rc.MAX_IN_FLIGHT) return; // Only clean up resources queued MAX_IN_FLIGHT ago (safety check for startup)
        const start = if (rc.RESOURCE_DEBUG == true) std.time.microTimestamp() else 0;

        const bufCount = self.resStorages[flightId].cleanupBuffers(self.vma, &self.descMan);
        const texCount = self.resStorages[flightId].cleanupTextures(self.vma, &self.descMan);

        if (rc.RESOURCE_DEBUG == true and bufCount + texCount > 0) {
            const time = @as(f64, @floatFromInt(std.time.microTimestamp() - start)) / 1_000.0;
            std.debug.print("Destroyed Buffers ({}) Textures ({}) (in Frame {}) (FlightId {}) {d:.3} ms\n", .{ bufCount, texCount, curFrame, flightId, time });
        }
    }

    pub fn getBufferDescriptor(self: *ResourceMan, bufId: BufferMeta.BufId, flightId: u8) !u32 {
        const bufMeta = try self.getBufferMeta(bufId);
        const realIndex = switch (bufMeta.update) {
            .Overwrite => 0,
            .PerFrame => if (bufMeta.typ == .Indirect) flightId else bufMeta.updateId, // Indirect written by GPU so always current flightId.
        };
        return (try self.descMan.getBufferDescriptor(bufId, realIndex));
    }

    pub fn getTextureDescriptor(self: *ResourceMan, texId: TextureMeta.TexId, flightId: u8) !u32 {
        const texMeta = try self.getTextureMeta(texId);
        const realIndex = switch (texMeta.update) {
            .Overwrite => 0,
            .PerFrame => flightId,
        };
        return (try self.descMan.getTextureDescriptor(texId, realIndex));
    }

    pub fn resetTransfers(self: *ResourceMan, flightId: u8) void {
        self.resStorages[flightId].resetTransfers();
    }

    pub fn getTexture(self: *ResourceMan, texId: TextureMeta.TexId, flightId: u8) !*Texture {
        const texMeta = try self.getTextureMeta(texId);
        const realIndex = switch (texMeta.update) {
            .Overwrite => 0,
            .PerFrame => flightId,
        };
        return try self.resStorages[realIndex].getTexture(texId);
    }

    pub fn getBuffer(self: *ResourceMan, bufId: BufferMeta.BufId, flightId: u8) !*Buffer {
        const bufMeta = try self.getBufferMeta(bufId);
        const realIndex = switch (bufMeta.update) {
            .Overwrite => 0,
            .PerFrame => if (bufMeta.typ == .Indirect) flightId else bufMeta.updateId, // Indirect written by GPU so always current flightId.
        };
        return try self.resStorages[realIndex].getBuffer(bufId);
    }

    pub fn getTextureMeta(self: *ResourceMan, texId: TextureMeta.TexId) !*TextureMeta {
        if (self.texMetas.isKeyUsed(texId.val) == true) return self.texMetas.getPtrByKey(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn getBufferMeta(self: *ResourceMan, bufId: BufferMeta.BufId) !*BufferMeta {
        if (self.bufMetas.isKeyUsed(bufId.val) == true) return self.bufMetas.getPtrByKey(bufId.val) else return error.BufferIdNotUsed;
    }

    fn initBuffer(self: *ResourceMan, bufInf: BufferMeta.BufInf, flightId: u8) !*Buffer {
        const buf = try self.vma.allocDefinedBuffer(bufInf);
        self.resStorages[flightId].addBuffer(bufInf.id, buf);
        return try self.resStorages[flightId].getBuffer(bufInf.id);
    }

    fn initTexture(self: *ResourceMan, texInf: TextureMeta.TexInf, flightId: u8) !*Texture {
        const tex = try self.vma.allocDefinedTexture(texInf);
        self.resStorages[flightId].addTexture(texInf.id, tex);
        return try self.resStorages[flightId].getTexture(texInf.id);
    }

    pub fn createBuffer(self: *ResourceMan, bufInf: BufferMeta.BufInf) !void {
        for (0..bufInf.update.getCount()) |i| {
            const flightId: u8 = @intCast(i);

            const buf = try self.initBuffer(bufInf, flightId);
            const initialBytes = bufInf.len * bufInf.elementSize;
            try self.updateBufferDescriptor(buf, bufInf.id, bufInf.typ, initialBytes, bufInf.elementSize, flightId);

            const descIndex = try self.descMan.getBufferDescriptor(bufInf.id, flightId);
            std.debug.print("Buffer created! (ID {}) (FlightId {}) ({}) ({}) (Descriptor {})\n", .{ bufInf.id.val, i, bufInf.typ, bufInf.update, descIndex });
            self.vma.printMemoryInfo(buf.allocation);
        }
        self.bufMetas.upsert(bufInf.id.val, self.vma.createBufferMeta(bufInf));
    }

    pub fn createTexture(self: *ResourceMan, texInf: TextureMeta.TexInf) !void {
        const texMeta: TextureMeta = self.vma.createTextureMeta(texInf);
        for (0..texInf.update.getCount()) |i| {
            const flightId: u8 = @intCast(i);

            const tex = try self.initTexture(texInf, flightId);
            try self.descMan.queueTextureDescriptor(&texMeta, tex.img, texInf.id, flightId);

            const descIndex = try self.descMan.getTextureDescriptor(texInf.id, flightId);
            std.debug.print("Texture created! (ID {}) (FlightId {}) ({}) ({}) (Descriptor {})\n", .{ texInf.id.val, i, texInf.typ, texInf.update, descIndex });
            self.vma.printMemoryInfo(tex.allocation);
        }
        self.texMetas.upsert(texInf.id.val, texMeta);
    }

    pub fn updateBuffer(self: *ResourceMan, bufInf: BufferMeta.BufInf, data: anytype, flightId: u8) !void {
        const bytes = try convertToByteSlice(data);
        const bufMeta = try self.getBufferMeta(bufInf.id);
        const realFlightId = switch (bufMeta.update) {
            .Overwrite => 0,
            .PerFrame => flightId,
        };

        var buf = try self.resStorages[realFlightId].getBuffer(bufInf.id);
        buf = try self.updateBufferSize(buf, bufInf, bytes.len, realFlightId);
        try self.uploadBufferData(buf, bufInf, bytes, realFlightId);
        try self.updateBufferDescriptor(buf, bufInf.id, bufMeta.typ, bytes.len, bufInf.elementSize, flightId);

        switch (bufMeta.update) {
            .Overwrite => {},
            .PerFrame => bufMeta.updateId = flightId,
        }
    }

    fn updateBufferSize(self: *ResourceMan, oldBuf: *Buffer, bufInf: BufferMeta.BufInf, bytesLength: usize, realFlightId: u8) !*Buffer {
        switch (bufInf.resize) {
            .Block => {
                if (bytesLength > oldBuf.size) return error.BufferBaseTooSmallForUpdate;
                return oldBuf;
            },
            .Grow, .Fit => {
                if ((bufInf.resize == .Fit and bytesLength != oldBuf.size) or
                    (bufInf.resize == .Grow and bytesLength > oldBuf.size))
                {
                    var newInf = bufInf;
                    newInf.len = @intCast((bytesLength + bufInf.elementSize - 1) / bufInf.elementSize);

                    std.debug.print("Buffer resized! (ID {}) (Container {}) ({}) ({})", .{ newInf.id.val, realFlightId, newInf.typ, newInf.update });
                    std.debug.print(" Length {} ({} Bytes) -> Length {} ({} Bytes) ", .{ bufInf.len, oldBuf.size, newInf.len, bytesLength });

                    try self.resStorages[realFlightId].queueBufferKill(newInf.id, self.descMan.removeBufferDescriptor(newInf.id, realFlightId));

                    const newBuf = try self.initBuffer(newInf, realFlightId);
                    self.vma.printMemoryInfo(newBuf.allocation);
                    return newBuf;
                }
                return oldBuf;
            },
        }
    }

    fn uploadBufferData(self: *ResourceMan, buf: *Buffer, bufInf: BufferMeta.BufInf, bytes: []const u8, realFlightId: u8) !void {
        switch (bufInf.mem) {
            .Gpu => try self.resStorages[realFlightId].stageBufferUpdate(bufInf.id, bytes),
            .CpuWrite => {
                const pMappedData = buf.mappedPtr orelse return error.BufferNotMapped;
                const destPtr: [*]u8 = @ptrCast(pMappedData);
                @memcpy(destPtr[0..bytes.len], bytes);
            },
            .CpuRead => return error.CpuReadBufferCantUpdate,
        }
    }

    fn updateBufferDescriptor(self: *ResourceMan, buf: *Buffer, bufId: BufferMeta.BufId, bufTyp: vhE.BufferType, bytesLength: usize, elementSize: usize, flightId: u8) !void {
        const newCount: u32 = @intCast(bytesLength / elementSize);

        if (buf.curCount != newCount) {
            buf.curCount = newCount;
            const activeByteSize = buf.curCount * elementSize;
            try self.descMan.queueBufferDescriptor(buf.gpuAddress, activeByteSize, bufTyp, bufId, flightId);

            if (rc.DESCRIPTOR_DEBUG == true) {
                const descIndex = try self.descMan.getBufferDescriptor(bufId, flightId);
                std.debug.print("Descriptor updated! (Index {}) (Buffer ID {})\n", .{ descIndex, bufId.val });
            }
        }
    }

    pub fn queueTextureKills(self: *ResourceMan, texId: TextureMeta.TexId) !void {
        const texMeta = try self.getTextureMeta(texId);
        for (0..texMeta.update.getCount()) |i| {
            const descIndex = self.descMan.removeTextureDescriptor(texId, @intCast(i));
            try self.resStorages[i].queueTextureKill(texId, descIndex);
        }
        self.texMetas.remove(texId.val);
    }

    // queueBufferKills: same pattern
    pub fn queueBufferKills(self: *ResourceMan, bufId: BufferMeta.BufId) !void {
        const bufMeta = try self.getBufferMeta(bufId);
        for (0..bufMeta.update.getCount()) |i| {
            const descIndex = self.descMan.removeBufferDescriptor(bufId, @intCast(i));
            try self.resStorages[i].queueBufferKill(bufId, descIndex);
        }
        self.bufMetas.remove(bufId.val);
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
