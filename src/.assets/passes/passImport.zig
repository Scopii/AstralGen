pub const PassAttrib = @import("../../../src/render/types/pass/PassDefinition.zig").PassDefinition.PassAttribute;
pub const VertexAttribute = @import("../../../src/render/types/pass/VertexAttribute.zig").VertexAttribute;
pub const PassDefinition = @import("../../../src/render/types/pass/PassDefinition.zig").PassDefinition;

pub const ComputeExec = @import("../../../src/render/types/pass/PassInstance.zig").ComputeExec;
pub const ComputeIndirectExec = @import("../../../src/render/types/pass/PassInstance.zig").ComputeIndirectExec;
pub const TaskOrMeshIndirectExec = @import("../../../src/render/types/pass/PassInstance.zig").TaskOrMeshIndirectExec;
pub const VertexExec = @import("../../../src/render/types/pass/PassInstance.zig").VertexExec;
pub const VertexIndexedExec = @import("../../../src/render/types/pass/PassInstance.zig").VertexIndexedExec;

pub const VertexBufferSlot = @import("../../../src/render/types/pass/VertexBufferSlot.zig").VertexBufferSlot;
pub const IndexBufferSlot = @import("../../../src/render/types/pass/IndexBufferSlot.zig").IndexBufferSlot;
pub const AttachmentSlot = @import("../../../src/render/types/pass/AttachmentSlot.zig").AttachmentSlot;
pub const TextureSlot = @import("../../../src/render/types/pass/TextureSlot.zig").TextureSlot;
pub const BufferSlot = @import("../../../src/render/types/pass/BufferSlot.zig").BufferSlot;

pub const TextureStringLink = @import("../../../src/renderGraph/components.zig").TextureStringLink;
pub const BufferStringLink = @import("../../../src/renderGraph/components.zig").BufferStringLink;

pub const ShaderInf = @import("../../../src/shader/ShaderInf.zig").ShaderInf;

pub const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
pub const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
pub const TexId = @import("../../.configs/idConfig.zig").TexId;
pub const BufId = @import("../../.configs/idConfig.zig").BufId;
