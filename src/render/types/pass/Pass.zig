const PassExecution = @import("PassDef.zig").PassDef.PassExecution;
const TexId = @import("../res/TextureMeta.zig").TextureMeta.TexId;
const BufId = @import("../res/BufferMeta.zig").BufferMeta.BufId;

pub const Pass = struct {
    name: []const u8,

    bufCount: u8 = 0,
    bufUses: [14]BufId = undefined,

    texCount: u8 = 0,
    texUses: [14]TexId = undefined,

    colorAttCount: u8 = 0,
    colorAtts: [8]TexId = undefined,
    depthAtt: ?TexId = null,
    stencilAtt: ?TexId = null,
};
