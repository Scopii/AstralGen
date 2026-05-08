const TextureMeta = @import("../res/TextureMeta.zig").TextureMeta;
const Texture = @import("../res/Texture.zig").Texture;
const vk = @import("../../../.modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");
const TexId = TextureMeta.TexId;

pub const AttachmentUse = struct {
    texId: TextureMeta.TexId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    clear: ?ClearColor,

    pub const ClearColor = union(enum) { color: [4]f32, depthStencil: vk.VkClearDepthStencilValue };

    pub fn init(id: TexId, stage: vhE.PipeStage, access: vhE.PipeAccess, layout: vhE.ImageLayout, clear: ?ClearColor) AttachmentUse {
        return .{ .texId = id, .stage = stage, .access = access, .layout = layout, .clear = clear };
    }

    pub fn getNeededState(self: *const AttachmentUse) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};
