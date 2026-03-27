const ShaderId = @import("../../../shader/ShaderSys.zig").ShaderId;
const RenderState = @import("../base/RenderState.zig").RenderState;
const TextureMeta = @import("../res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../res/BufferMeta.zig").BufferMeta;
const Texture = @import("../res/Texture.zig").Texture;
const Buffer = @import("../res/Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");
const TexId = TextureMeta.TexId;
const Pass = @import("Pass.zig").Pass;

// pub const TargetAction = enum { clear, load };

pub const PassUsage = struct {
    name: []const u8,
    pass: Pass,

    pushConstants: extern struct {
        objectBufferId: u32,
        cameraBufferId: u32,
        renderTexId: u32,
    },
};

pub const Attachment = struct {
    typ: enum {Color, Depth, Stencil},
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout = .General,
};

pub const AttachmentSlot = struct {
    texId: TextureMeta.TexId,
};

pub const TextureDefinition = struct {
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout = .General,
    shaderSlot: ?u32 = null,
};

pub const TextureSlot = struct {
    texId: TextureMeta.TexId,
};

pub const BufferDefinition = struct {
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    shaderSlot: ?u32 = null,
};

pub const BufferSlot = struct {
    bufId: BufferMeta.BufId,
};
