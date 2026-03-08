const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../structures/LinkedMap.zig").LinkedMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const rH = @import("ResHelpers.zig");

pub const ResourceQueue = struct {
    bufCreations: LinkedMap(BufferMeta.BufInf, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    texCreations: LinkedMap(TextureMeta.TexInf, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},
    bufDeletions: FixedList(Buffer, rc.BUF_MAX) = .{},
    texDeletions: FixedList(Texture, rc.TEX_MAX) = .{},

    pub fn addCreation(self: *ResourceQueue, inf: anytype) void {
        self.creationMapOf(rH.ResOfInf(@TypeOf(inf))).upsert(inf.id.val, inf);
    }

    pub fn addDeletion(self: *ResourceQueue, val: anytype) !void {
        try self.deletionListOf(@TypeOf(val)).append(val);
    }

    pub fn getCreations(self: *ResourceQueue, comptime T: type) []rH.InfOfRes(T) {
        return self.creationMapOf(T).getItems();
    }

    pub fn getDeletions(self: *ResourceQueue, comptime T: type) []T {
        return self.deletionListOf(T).slice();
    }

    pub fn checkCreation(self: *ResourceQueue, id: anytype) ?*rH.InfOfId(@TypeOf(id)) {
        const map = self.creationMapOf(rH.ResOfId(@TypeOf(id)));
        return if (map.isKeyUsed(id.val)) map.getPtrByKey(id.val) else null;
    }

    pub fn invalidateCreation(self: *ResourceQueue, id: anytype) void {
        const map = self.creationMapOf(rH.ResOfId(@TypeOf(id)));
        if (map.isKeyUsed(id.val)) map.remove(id.val);
    }

    pub fn clearCreations(self: *ResourceQueue, comptime T: type) void {
        self.creationMapOf(T).clear();
    }

    pub fn clearDeletions(self: *ResourceQueue, comptime T: type) void {
        self.deletionListOf(T).clear();
    }

    fn creationMapOf(self: *ResourceQueue, comptime T: type) switch (T) {
        Buffer => *@TypeOf(self.bufCreations),
        Texture => *@TypeOf(self.texCreations),
        else => @compileError("unsupported type"),
    } {
        return switch (T) {
            Buffer => &self.bufCreations,
            Texture => &self.texCreations,
            else => unreachable,
        };
    }

    fn deletionListOf(self: *ResourceQueue, comptime T: type) switch (T) {
        Buffer => *@TypeOf(self.bufDeletions),
        Texture => *@TypeOf(self.texDeletions),
        else => @compileError("unsupported type"),
    } {
        return switch (T) {
            Buffer => &self.bufDeletions,
            Texture => &self.texDeletions,
            else => unreachable,
        };
    }
};
