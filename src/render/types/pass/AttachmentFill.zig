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

    pub fn init(texId: TexId, stage: vhE.PipeStage, access: vhE.PipeAccess, clear: ?ClearValue) AttachmentFill {
        const layout: vhE.ImageLayout = if (access.isReadOnly() == true) .ReadOnly else .Attachment;

        return .{
            .texId = texId,
            .stage = stage,
            .access = access,
            .layout = layout,
            .clear = clear,
        };
    }

    pub fn getNeededState(self: *const AttachmentFill) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};
