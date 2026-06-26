pub const VertexBufferUse = @import("../../../src/render/types/pass/VertexBufferUse.zig").VertexBufferUse;
pub const VertexAttribute = @import("../../../src/render/types/pass/VertexAttribute.zig").VertexAttribute;
pub const IndexBufferUse = @import("../../../src/render/types/pass/IndexBufferUse.zig").IndexBufferUse;
pub const AttachmentUse = @import("../../../src/render/types/pass/AttachmentUse.zig").AttachmentUse;
pub const TextureUse = @import("../../../src/render/types/pass/TextureUse.zig").TextureUse;
pub const BufferUse = @import("../../../src/render/types/pass/BufferUse.zig").BufferUse;

pub const TextureLink = @import("../../../src/frameBuild/components.zig").TextureLink;
pub const BufferLink = @import("../../../src/frameBuild/components.zig").BufferLink;

pub const PassDef = @import("../../../src/render/types/pass/PassDef.zig").PassDef;

pub const TexPassId = @import("../../../src/frameBuild/components.zig").TexPassId;
pub const BufPassId = @import("../../../src/frameBuild/components.zig").BufPassId;

pub const PassDefinition = @import("../../../src/render/types/pass/PassDefinition.zig").PassDefinition;
pub const PassAttrib = @import("../../../src/render/types/pass/PassDefinition.zig").PassDefinition.PassAttribute;

pub const ComputeExec = @import("../../../src/render/types/pass/PassDef.zig").ComputeExec;
pub const ComputeIndirectExec = @import("../../../src/render/types/pass/PassDef.zig").ComputeIndirectExec;
pub const TaskOrMeshIndirectExec = @import("../../../src/render/types/pass/PassDef.zig").TaskOrMeshIndirectExec;
pub const GraphicsExec = @import("../../../src/render/types/pass/PassDef.zig").GraphicsExec;

pub const VertexBufferSlot = @import("../../../src/render/types/pass/VertexBufferSlot.zig").VertexBufferSlot;
pub const IndexBufferSlot = @import("../../../src/render/types/pass/IndexBufferSlot.zig").IndexBufferSlot;
pub const AttachmentSlot = @import("../../../src/render/types/pass/AttachmentSlot.zig").AttachmentSlot;
pub const TextureSlot = @import("../../../src/render/types/pass/TextureSlot.zig").TextureSlot;
pub const BufferSlot = @import("../../../src/render/types/pass/BufferSlot.zig").BufferSlot;

pub const TextureStringLink = @import("../../../src/frameBuild/components.zig").TextureStringLink;
pub const BufferStringLink = @import("../../../src/frameBuild/components.zig").BufferStringLink;

pub const ShaderInf = @import("../../../src/shader/ShaderInf.zig").ShaderInf;
