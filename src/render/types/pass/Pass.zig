const FixedList = @import("../../../.structures/FixedList.zig").FixedList;
const PassExecution = @import("PassDef.zig").PassDef.PassExecution;
const TexId = @import("../res/TextureMeta.zig").TextureMeta.TexId;
const BufId = @import("../res/BufferMeta.zig").BufferMeta.BufId;

pub const Pass = struct {
    name: []const u8,

    bufUses: FixedList(BufId, 14) = .{},
    texUses: FixedList(BufId, 14) = .{},
    colorAtts: FixedList(BufId, 8) = .{},
    depthAtt: ?TexId = null,
    stencilAtt: ?TexId = null,
};
