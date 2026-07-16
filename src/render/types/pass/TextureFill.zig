const TexId = @import("../../../.configs/idConfig.zig").TexId;
const Texture = @import("../res/Texture.zig").Texture;
const vhE = @import("../../help/Enums.zig");

pub const TextureFill = struct {
    texId: TexId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    descUse: vhE.TexDescriptor,
    shaderSlot: ?u32 = null,
};
