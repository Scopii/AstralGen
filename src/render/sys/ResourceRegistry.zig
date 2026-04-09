const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../.configs/renderConfig.zig");
const vhE = @import("../help/Enums.zig");
const rH = @import("ResHelpers.zig");
const Vma = @import("Vma.zig").Vma;

pub const ResourceBucket = struct {
    buffers: LinkedMap(Buffer, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    textures: LinkedMap(Texture, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    pub fn deinit(self: *ResourceBucket, vma: *const Vma) void {
        for (self.buffers.getItems()) |*bufBase| vma.freeBuffer(bufBase);
        for (self.textures.getItems()) |*texBase| vma.freeTexture(texBase);
    }

    fn mapOf(self: *ResourceBucket, comptime T: type) switch (T) {
        Buffer => *@TypeOf(self.buffers),
        Texture => *@TypeOf(self.textures),
        else => @compileError("mapOf: unsupported type"),
    } {
        return switch (T) {
            Buffer => &self.buffers,
            Texture => &self.textures,
            else => unreachable,
        };
    }
};

pub const ResourceRegistry = struct {
    bufMetas: LinkedMap(BufferMeta, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    texMetas: LinkedMap(TextureMeta, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},
    staticHolder: ResourceBucket = .{},
    dynHolders: [rc.MAX_IN_FLIGHT]ResourceBucket,

    pub fn init() ResourceRegistry {
        var dynHolders: [rc.MAX_IN_FLIGHT]ResourceBucket = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| dynHolders[i] = .{};

        return .{ .dynHolders = dynHolders };
    }

    pub fn deinit(self: *ResourceRegistry, vma: *const Vma) void {
        for (0..rc.MAX_IN_FLIGHT) |i| {
            self.dynHolders[i].deinit(vma);
        }
        self.staticHolder.deinit(vma);
    }

    // Meta
    pub fn addMeta(self: *ResourceRegistry, id: anytype, meta: anytype) void {
        self.metaMapOf(rH.ResOfId(@TypeOf(id))).upsert(id.val, meta);
    }

    pub fn getMeta(self: *ResourceRegistry, id: anytype) !*rH.MetaOfId(@TypeOf(id)) {
        const map = self.metaMapOf(rH.ResOfId(@TypeOf(id)));
        return if (map.isKeyUsed(id.val)) map.getPtrByKey(id.val) else error.GetMetaIdNotUsed;
    }

    pub fn removeMeta(self: *ResourceRegistry, id: anytype) void {
        self.metaMapOf(rH.ResOfId(@TypeOf(id))).remove(id.val);
    }

    // Resources
    pub fn add(self: *ResourceRegistry, id: anytype, val: anytype, updateTyp: vhE.UpdateType, flightId: u8) *@TypeOf(val) {
        const map = self.getHolder(updateTyp, flightId).mapOf(@TypeOf(val));
        map.upsert(id.val, val);
        return map.getPtrByKey(id.val);
    }

    pub fn get(self: *ResourceRegistry, id: anytype, updateTyp: vhE.UpdateType, flightId: u8, updateSlot: u8) !*rH.ResOfId(@TypeOf(id)) {
        const map = self.getResHolder(updateTyp, flightId, updateSlot).mapOf(rH.ResOfId(@TypeOf(id)));
        return if (map.isKeyUsed(id.val)) map.getPtrByKey(id.val) else error.GetIdNotUsed;
    }

    pub fn remove(self: *ResourceRegistry, id: anytype, updateTyp: vhE.UpdateType, flightId: u8) ?rH.ResOfId(@TypeOf(id)) {
        const map = self.getHolder(updateTyp, flightId).mapOf(rH.ResOfId(@TypeOf(id)));
        if (!map.isKeyUsed(id.val)) return null;
        const res = map.getPtrByKey(id.val).*;
        map.remove(id.val);
        return res;
    }

    pub fn check(self: *ResourceRegistry, id: anytype, updateTyp: vhE.UpdateType, flightId: u8, updateSlot: u8) ?*rH.ResOfId(@TypeOf(id)) {
        const map = self.getResHolder(updateTyp, flightId, updateSlot).mapOf(rH.ResOfId(@TypeOf(id)));
        return if (map.isKeyUsed(id.val)) map.getPtrByKey(id.val) else null;
    }

    // Helper
    fn getHolder(self: *ResourceRegistry, updateTyp: vhE.UpdateType, flightId: u8) *ResourceBucket {
        return switch (updateTyp) {
            .Rarely => &self.staticHolder,
            .Often, .PerFrame => &self.dynHolders[flightId],
        };
    }

    fn getResHolder(self: *ResourceRegistry, updateTyp: vhE.UpdateType, flightId: u8, updateSlot: u8) *ResourceBucket {
        return switch (updateTyp) {
            .Rarely => &self.staticHolder,
            .Often => &self.dynHolders[updateSlot],
            .PerFrame => &self.dynHolders[flightId],
        };
    }

    fn metaMapOf(self: *ResourceRegistry, comptime T: type) switch (T) {
        Buffer => *@TypeOf(self.bufMetas),
        Texture => *@TypeOf(self.texMetas),
        else => @compileError("mapOf: unsupported type"),
    } {
        return switch (T) {
            Buffer => &self.bufMetas,
            Texture => &self.texMetas,
            else => unreachable,
        };
    }
};
