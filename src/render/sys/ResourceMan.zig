const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const ResourceUpdater = @import("ResourceUpdater.zig").ResourceUpdater;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const DescriptorMan = @import("DescriptorMan.zig").DescriptorMan;
const KeyPool = @import("../../.structures/KeyPool.zig").KeyPool;
const Texture = @import("../types/res/Texture.zig").Texture;
const TexId = @import("../../.configs/idConfig.zig").TexId;
const BufId = @import("../../.configs/idConfig.zig").BufId;
const TexInf = @import("../types/res/Texture.zig").TexInf;
const BufInf = @import("../types/res/Buffer.zig").BufInf;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../.configs/renderConfig.zig");
const vk = @import("../../.modules/vk.zig").c;
const Context = @import("Context.zig").Context;
const vhT = @import("../help/Types.zig");
const vhE = @import("../help/Enums.zig");
const Allocator = std.mem.Allocator;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

pub const ResourceMan = struct {
    vma: Vma,
    alloc: Allocator,
    descMan: DescriptorMan,
    updater: ResourceUpdater,

    buffers: LinkedIdMap(Buffer, rc.BUF_MAX * rc.MAX_IN_FLIGHT, BufId, rc.BUF_MAX * rc.MAX_IN_FLIGHT, 0) = .{},
    textures: LinkedIdMap(Texture, rc.TEX_MAX * rc.MAX_IN_FLIGHT, TexId, rc.TEX_MAX * rc.MAX_IN_FLIGHT, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const vma = try Vma.init(context.instance, context.gpi, context.gpu);

        return .{
            .vma = vma,
            .alloc = alloc,
            .updater = try ResourceUpdater.init(alloc, &vma),
            .descMan = try DescriptorMan.init(&vma, context.gpu),
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        self.updater.deinit(&self.vma);
        for (self.buffers.getConstItems()) |*buf| self.vma.freeBuffer(buf);
        for (self.textures.getConstItems()) |*tex| self.vma.freeTexture(tex);
        self.descMan.deinit(&self.vma);
        self.vma.deinit();
    }

    pub fn update(self: *ResourceMan, flightId: u8, curFrame: u64) !void {
        // if (rc.GPU_READBACK == true) try self.printReadbackBuf(rc.readbackSB.id, vhT.ReadbackData);
        try self.descMan.updateDescriptors(self.vma.gpi, flightId);
        if (false) std.debug.print("ResMan Updated (Frame {}) (Flight {})\n", .{ curFrame, flightId });
    }

    pub fn getBuf(self: *ResourceMan, id: BufId) !*const Buffer {
        if (self.buffers.isKeyUsed(id)) return self.buffers.getConstPtrByKey(id) else {
            std.debug.print("ERROR: ResourceMan: id {} (Type {}) not found\n", .{ id, @TypeOf(id) });
            return error.GetIdNotUsed;
        }
    }

    pub fn getTex(self: *ResourceMan, id: TexId) !*const Texture {
        if (self.textures.isKeyUsed(id)) return self.textures.getConstPtrByKey(id) else {
            std.debug.print("ERROR: ResourceMan: id {} (Type {}) not found\n", .{ id, @TypeOf(id) });
            return error.GetIdNotUsed;
        }
    }

    pub fn getBufDescriptor(self: *ResourceMan, id: BufId) !u32 {
        const buf = try self.getBuf(id);
        return buf.descIndex orelse error.ResIdHasNoDescriptor;
    }

    pub fn getTexDescriptor(self: *ResourceMan, id: TexId, texDescriptor: vhE.TexDescriptor) !u32 {
        const tex = try self.getTex(id);
        return switch (texDescriptor) {
            .Storage => tex.descIndex orelse error.ResIdHasNoDescriptor,
            .Sampled => tex.sampledDescIndex orelse error.ResIdHasNoDescriptor,
        };
    }

    pub fn addTex(self: *ResourceMan, inf: TexInf, curFrame: u64, flightId: u8, data: anytype) !void {
        var tex = try self.vma.allocDefinedTexture(&inf);
        try self.descMan.queueTextureDescriptor(&tex);
        self.textures.upsert(inf.id, tex);

        if (rc.RESOURCE_DEBUG == true) {
            std.debug.print("Texture (ID {}) Created! ", .{inf.id.val()});
            self.vma.printMemoryInfo(tex.allocation);
        }

        if (data != null) try self.updateTex(inf.id, curFrame, flightId, data);
        if (rc.RESOURCE_DEBUG == true) std.debug.print("Texture added! (ID {}) (Frame {}) ({}) ({})\n", .{ inf.id.val(), curFrame, inf.typ, tex.update });
    }

    pub fn addBuf(self: *ResourceMan, inf: BufInf, curFrame: u64, flightId: u8, data: anytype) !void {
        var buf = try self.vma.allocDefinedBuffer(&inf);

        try self.descMan.queueBufferDescriptor(buf.gpuAddress, inf.len * inf.elementSize, inf.typ, &buf);
        self.buffers.upsert(inf.id, buf);

        if (rc.RESOURCE_DEBUG == true) {
            std.debug.print("Buffer (ID {}) Created! ", .{inf.id.val()});
            self.vma.printMemoryInfo(buf.allocation);
        }

        if (data != null) try self.updateBuf(inf.id, curFrame, flightId, data);
        if (rc.RESOURCE_DEBUG == true) std.debug.print("Buffer added! (ID {}) (Frame {}) ({}) ({})\n", .{ inf.id.val(), curFrame, inf.typ, buf.update });
    }

    pub fn removeTex(self: *ResourceMan, id: TexId, curFrame: u64) !void {
        const tex = self.textures.getConstPtrByKey(id);
        self.vma.freeTexture(tex);
        if (tex.descIndex) |descIndex| self.descMan.freeDescriptorIndex(descIndex);
        if (tex.sampledDescIndex) |sampledDescIndex| self.descMan.freeDescriptorIndex(sampledDescIndex);
        self.textures.remove(id);

        if (rc.RESOURCE_DEBUG == true) std.debug.print("Texture Removed! (ID {}) (Frame {})\n", .{ id.val(), curFrame });
    }

    pub fn removeBuf(self: *ResourceMan, id: BufId, curFrame: u64) !void {
        const buf = self.buffers.getConstPtrByKey(id);
        self.vma.freeBuffer(buf);
        if (buf.descIndex) |descIndex| self.descMan.freeDescriptorIndex(descIndex);
        self.buffers.remove(id);

        if (rc.RESOURCE_DEBUG == true) std.debug.print("Buffer Removed! (ID {}) (Frame {})\n", .{ id.val(), curFrame });
    }

    pub fn updateTex(self: *ResourceMan, texId: TexId, curFrame: u64, flightId: u8, data: anytype) !void {
        const bytes = try convertToByteSlice(data);
        const tex = self.textures.getPtrByKey(texId);
        try self.updater.stageTextureUpdate(texId, bytes, tex.extent.width, tex.extent.height, flightId);
        if (false) std.debug.print("ResourceMan: Staged TexUpdate (TexId {}) (Frame {})\n", .{ texId.val(), curFrame });
    }

    pub fn updateBuf(self: *ResourceMan, bufId: BufId, curFrame: u64, flightId: u8, data: anytype) !void {
        const bytes = try convertToByteSlice(data);
        try self.updater.stageBufferUpdate(bufId, bytes, flightId);
        if (false) std.debug.print("ResourceMan: Staged BufUpdate (BufId {}) (Frame {})\n", .{ bufId.val(), curFrame });
    }

    pub fn updateBufSegment(self: *ResourceMan, bufId: BufId, flightId: u8, data: anytype, element: u32) !void {
        const buf = try self.getBuf(bufId);
        const bytes = try convertToByteSlice(data);
        const elementOffset: u64 = @as(u64, buf.elementSize) * element;

        if (elementOffset + bytes.len > buf.size) return error.SegmentWriteOutOfBounds;
        try self.updater.stageBufferSegmentUpdate(bufId, bytes, flightId, elementOffset);
    }

    fn getBufDataPtr(self: *ResourceMan, bufId: BufId, comptime T: type) !*T {
        const buf = try self.getBuf(bufId);
        if (buf.mappedPtr) |ptr| {
            return @as(*T, @ptrCast(@alignCast(ptr)));
        }
        return error.BufferNotHostVisible;
    }

    // fn printReadbackBuf(self: *ResourceMan, bufId: BufId, comptime T: type) !void {
    //     const readbackPtr = try self.getBufDataPtr(bufId, T);
    //     std.debug.print("Readback: {}\n", .{readbackPtr.*});
    // }
};

pub fn convertToByteSlice(data: anytype) ![]const u8 {
    const DataType = @TypeOf(data);
    return switch (@typeInfo(DataType)) {
        .optional => if (data) |d| convertToByteSlice(d) else error.ExpectedPointer,
        .pointer => |ptr| switch (ptr.size) {
            .one => std.mem.asBytes(data),
            .slice => std.mem.sliceAsBytes(data),
            else => return error.UnsupportedPointerType,
        },
        else => return error.ExpectedPointer,
    };
}

pub fn typeName(comptime T: type) []const u8 {
    const name = @typeName(T);
    return if (std.mem.lastIndexOfScalar(u8, name, '.')) |i| name[i + 1 ..] else name;
}
