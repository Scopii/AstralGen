const TextureMeta = @import("../res/TextureMeta.zig").TextureMeta;
const Texture = @import("../res/Texture.zig").Texture;
const vhE = @import("../../help/Enums.zig");
const TexId = TextureMeta.TexId;

pub const AttachmentUse = struct {
    texId: TextureMeta.TexId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    clear: bool,

    pub fn init(id: TexId, stage: vhE.PipeStage, access: vhE.PipeAccess, clear: bool) AttachmentUse {
        return .{ .texId = id, .stage = stage, .access = access, .layout = .Attachment, .clear = clear };
    }

    pub fn getNeededState(self: *const AttachmentUse) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};
