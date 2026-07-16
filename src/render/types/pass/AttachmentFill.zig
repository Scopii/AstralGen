const ClearValue = @import("AttachmentSlot.zig").AttachmentSlot.ClearValue;
const TexId = @import("../../../.configs/idConfig.zig").TexId;
const Texture = @import("../res/Texture.zig").Texture;
const vk = @import("../../../.modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const AttachmentFill = struct {
    texId: TexId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    clear: ?ClearValue,
};
