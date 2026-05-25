const Texture = @import("../res/Texture.zig").Texture;
const vhE = @import("../../help/Enums.zig");

const TextureLink = @import("../../../frameBuild/components.zig").TextureLink;

pub const TextureUse = struct {
    texLink: TextureLink,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    descUse: vhE.TexDescriptor,
    shaderSlot: ?u32 = null,

    pub fn init(texLink: TextureLink, stage: vhE.PipeStage, access: vhE.PipeAccess, layout: vhE.ImageLayout, shaderSlot: ?u8, descUse: vhE.TexDescriptor) TextureUse {
        return .{ .texLink = texLink, .stage = stage, .access = access, .layout = layout, .shaderSlot = if (shaderSlot) |slot| slot else null, .descUse = descUse };
    }

    pub fn getNeededState(self: *const TextureUse) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};
