const TextureStringLink = @import("../../../renderGraph/components.zig").TextureStringLink;
const TexId = @import("../../../.configs/idConfig.zig").TexId;
const Texture = @import("../res/Texture.zig").Texture;
const vk = @import("../../../.modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const ClearColor = struct { R: f32, G: f32, B: f32, A: f32 };
pub const ClearDepth = struct { depthStencil: vk.VkClearDepthStencilValue };
pub const ClearValue = union(enum) { color: ClearColor, depth: ClearDepth };

pub const AttachmentFill = struct {
    texId: TexId,
    stage: vhE.PipeStage,
    access: vhE.PipeAccess,
    layout: vhE.ImageLayout,
    clear: ?ClearValue,
};

pub const AttachmentSlot = struct {
    texLink: TextureStringLink,
    stage: vhE.PipeStage,
    access: vhE.PipeAccess,
    layout: vhE.ImageLayout,
    clear: ?ClearValue,

    pub fn init(texLink: TextureStringLink, stage: vhE.PipeStage, access: vhE.PipeAccess, clear: ?ClearValue) AttachmentSlot {
        const layout: vhE.ImageLayout = if (access.isReadOnly() == true) .ReadOnly else .Attachment;

        return .{
            .texLink = texLink,
            .stage = stage,
            .access = access,
            .layout = layout,
            .clear = clear,
        };
    }
};
