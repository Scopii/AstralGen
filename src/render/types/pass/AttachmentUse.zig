const TextureLink = @import("../../../frameBuild/components.zig").TextureLink;
const Texture = @import("../res/Texture.zig").Texture;
const vk = @import("../../../.modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const AttachmentUse = struct {
    texLink: TextureLink,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    clear: ?ClearColor,

    pub const ClearColor = union(enum) { color: [4]f32, depthStencil: vk.VkClearDepthStencilValue };

    pub fn init(texLink: TextureLink, stage: vhE.PipeStage, access: vhE.PipeAccess, clear: ?ClearColor) AttachmentUse {
        const layout: vhE.ImageLayout = if (access.isReadOnly() == true) .ReadOnly else .Attachment;

        return .{
            .texLink = texLink,
            .stage = stage,
            .access = access,
            .layout = layout,
            .clear = clear,
        };
    }

    pub fn getNeededState(self: *const AttachmentUse) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};
