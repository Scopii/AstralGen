const TextureMeta = @import("../res/TextureMeta.zig").TextureMeta;
const Texture = @import("../res/Texture.zig").Texture;
const vhE = @import("../../help/Enums.zig");
const TexId = TextureMeta.TexId;

pub const TextureUse = struct {
    texId: TextureMeta.TexId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    shaderSlot: ?u32 = null,

    pub fn init(id: TextureMeta.TexId, stage: vhE.PipeStage, access: vhE.PipeAccess, layout: vhE.ImageLayout, shaderSlot: ?u8) TextureUse {
        return .{ .texId = id, .stage = stage, .access = access, .layout = layout, .shaderSlot = if (shaderSlot) |slot| slot else null };
    }

    pub fn getNeededState(self: *const TextureUse) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};