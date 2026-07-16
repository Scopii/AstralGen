const FixedList = @import("../../../.structures/FixedList.zig").FixedList;
const VertexBufferFill = @import("VertexBufferFill.zig").VertexBufferFill;
const VertexAttribute = @import("VertexAttribute.zig").VertexAttribute;
const ShaderInf = @import("../../../shader/ShaderInf.zig").ShaderInf;
const ShaderId = @import("../../../.configs/idConfig.zig").ShaderId;
const RenderState = @import("../pass/RenderState.zig").RenderState;
const BufId = @import("../../../.configs/idConfig.zig").BufId;
const TexId = @import("../../../.configs/idConfig.zig").TexId;
const TextureFill = @import("TextureFill.zig").TextureFill;
const String = @import("../../../globalHelper.zig").String;
const std = @import("std");

pub const ComputeExec = struct { groupX: u32, groupY: u32, groupZ: u32, outputTexDispatch: bool };
pub const TaskOrMeshExec = struct { groupX: u32, groupY: u32, groupZ: u32 };
pub const VertexExec = struct { vertices: u32, instances: u32, firstVertex: u32, firstInstance: u32 };
pub const VertexIndexedExec = struct { indexCount: u32, instanceCount: u32, firstIndex: u32, vertexOffset: i32, firstInstance: u32 };

pub const ComputeIndirectExecSlot = struct { indirectBuf: []const u8, indirectBufOffset: u64 = 0 };
pub const TaskOrMeshIndirectExecSlot = struct { groupX: u32, groupY: u32, groupZ: u32, indirectBuf: []const u8, indirectBufOffset: u64 = 0 };

pub const ComputeIndirectExec = struct { indirectBuf: BufId, indirectBufOffset: u64 = 0 };
pub const TaskOrMeshIndirectExec = struct { groupX: u32, groupY: u32, groupZ: u32, indirectBuf: BufId, indirectBufOffset: u64 = 0 };

pub const PassExecution = union(enum) {
    compute: ComputeExec,
    computeIndirect: ComputeIndirectExec,
    taskOrMesh: TaskOrMeshExec,
    taskOrMeshIndirect: TaskOrMeshIndirectExec,
    vertex: VertexExec,
    vertexIndexed: VertexIndexedExec,
};

pub const PassExecutionSlot = union(enum) {
    compute: ComputeExec,
    computeIndirect: ComputeIndirectExecSlot,
    taskOrMesh: TaskOrMeshExec,
    taskOrMeshIndirect: TaskOrMeshIndirectExecSlot,
    vertex: VertexExec,
    vertexIndexed: VertexIndexedExec,
};
