const TextureStringLink = @import("../../../frameBuild/components.zig").TextureStringLink;
const Texture = @import("../res/Texture.zig").Texture;
const vk = @import("../../../.modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

const ClearColor = @import("AttachmentUse.zig").AttachmentUse.ClearColor;

pub const AttachmentSlot = struct {
    texLink: TextureStringLink,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    clear: ?ClearColor,

    // pub const ClearColor = union(enum) { color: [4]f32, depthStencil: vk.VkClearDepthStencilValue };

    pub fn init(texLink: TextureStringLink, stage: vhE.PipeStage, access: vhE.PipeAccess, clear: ?ClearColor) AttachmentSlot {
        const layout: vhE.ImageLayout = if (access.isReadOnly() == true) .ReadOnly else .Attachment;

        return .{
            .texLink = texLink,
            .stage = stage,
            .access = access,
            .layout = layout,
            .clear = clear,
        };
    }

    pub fn getNeededState(self: *const AttachmentSlot) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};
