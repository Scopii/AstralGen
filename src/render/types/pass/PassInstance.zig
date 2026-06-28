const FixedList = @import("../../../.structures/FixedList.zig").FixedList;
const VertexBufferFill = @import("VertexBufferFill.zig").VertexBufferFill;
const VertexAttribute = @import("VertexAttribute.zig").VertexAttribute;
const ShaderInf = @import("../../../shader/ShaderInf.zig").ShaderInf;
const IndexBufferFill = @import("IndexBufferFill.zig").IndexBufferFill;
const ShaderId = @import("../../../shader/ShaderSys.zig").ShaderId;
const RenderState = @import("../pass/RenderState.zig").RenderState;
const AttachmentFill = @import("AttachmentFill.zig").AttachmentFill;
const TextureFill = @import("TextureFill.zig").TextureFill;
const BufferFill = @import("BufferFill.zig").BufferFill;
const std = @import("std");

const BufId = @import("../res/BufferMeta.zig").BufferMeta.BufId;
const TexId = @import("../res/TextureMeta.zig").TextureMeta.TexId;

const String = @import("../../../globalHelper.zig").String;

pub const PassNode = struct { pass: PassInstance, passWidth: u32, passHeight: u32 };

pub const ComputeExec = struct { groupX: u32, groupY: u32, groupZ: u32, outputTexDispatch: bool };
pub const TaskOrMeshExec = struct { groupX: u32, groupY: u32, groupZ: u32 };
pub const GraphicsExec = struct { vertices: u32, instances: u32, indexCount: u32 };

pub const ComputeIndirectExecSlot = struct { indirectBuf: []const u8, indirectBufOffset: u64 = 0 };
pub const TaskOrMeshIndirectExecSlot = struct { groupX: u32, groupY: u32, groupZ: u32, indirectBuf: []const u8, indirectBufOffset: u64 = 0 };

pub const ComputeIndirectExec = struct { indirectBuf: BufId, indirectBufOffset: u64 = 0 };
pub const TaskOrMeshIndirectExec = struct { groupX: u32, groupY: u32, groupZ: u32, indirectBuf: BufId, indirectBufOffset: u64 = 0 };

pub const PassInstance = struct {
    name: String(30, "PASS_NAME_MISSING") = .{},
    execution: PassExecution,
    mainOutputTex: ?TexId,

    // All passes
    shaderIds: FixedList(ShaderId, 3) = .{},
    bufUses: FixedList(BufferFill, 14) = .{},
    texUses: FixedList(TextureFill, 14) = .{},

    // All Graphics Passes
    renderState: RenderState = .{},
    colorAtts: FixedList(AttachmentFill, 8) = .{},
    depthAtt: ?AttachmentFill = null,
    stencilAtt: ?AttachmentFill = null,

    // Vertex Passes Only
    vertexBuffers: FixedList(VertexBufferFill, 4) = .{},
    indexBuffer: ?IndexBufferFill = null,
    vertexAttributes: FixedList(VertexAttribute, 16) = .{},

    pub const PassExecution = union(enum) {
        compute: ComputeExec,
        computeIndirect: ComputeIndirectExec,
        taskOrMesh: TaskOrMeshExec,
        taskOrMeshIndirect: TaskOrMeshIndirectExec,
        graphics: GraphicsExec,
    };

    pub const PassExecutionSlot = union(enum) {
        compute: ComputeExec,
        computeIndirect: ComputeIndirectExecSlot,
        taskOrMesh: TaskOrMeshExec,
        taskOrMeshIndirect: TaskOrMeshIndirectExecSlot,
        graphics: GraphicsExec,
    };

    pub fn Graphics(
        inf: struct {
            name: []const u8,
            outputTexId: ?TexId,
            execution: GraphicsExec,
            vertex: ShaderInf,
            fragment: ShaderInf,
            bufUses: []const BufferFill = &.{},
            texUses: []const TextureFill = &.{},
            colorAtts: []const AttachmentFill = &.{},
            depthAtt: ?AttachmentFill = null,
            stencilAtt: ?AttachmentFill = null,
            renderState: RenderState = .{},
            vertexBuffers: []const VertexBufferFill = &.{},
            indexBuffer: ?IndexBufferFill = null,
            vertexAttributes: []const VertexAttribute = &.{},
        },
    ) PassInstance {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.vertex.typ == .vert);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = PassInstance{
            .mainOutputTex = inf.outputTexId,
            .execution = .{ .graphics = inf.execution },
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };
        pass.name.fill(inf.name);

        pass.shaderIds.appendAssumeCapacity(inf.vertex.id);
        pass.shaderIds.appendAssumeCapacity(inf.fragment.id);

        pass.bufUses.appendSliceAssumeCapacity(inf.bufUses);
        pass.texUses.appendSliceAssumeCapacity(inf.texUses);
        pass.colorAtts.appendSliceAssumeCapacity(inf.colorAtts);

        pass.vertexBuffers.appendSliceAssumeCapacity(inf.vertexBuffers);
        pass.vertexAttributes.appendSliceAssumeCapacity(inf.vertexAttributes);
        pass.indexBuffer = inf.indexBuffer;

        return pass;
    }

    pub fn Compute(
        inf: struct {
            name: []const u8,
            outputTexId: ?TexId,
            execution: ComputeExec,
            compute: ShaderInf,
            bufUses: []const BufferFill = &.{},
            texUses: []const TextureFill = &.{},
        },
    ) PassInstance {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.compute.typ == .comp);

        var pass = PassInstance{
            .mainOutputTex = inf.outputTexId,
            .execution = .{ .compute = inf.execution },
        };
        pass.name.fill(inf.name);

        pass.shaderIds.appendAssumeCapacity(inf.compute.id);

        pass.bufUses.appendSliceAssumeCapacity(inf.bufUses);
        pass.texUses.appendSliceAssumeCapacity(inf.texUses);

        return pass;
    }

    pub fn ComputeIndirect(
        inf: struct {
            name: []const u8,
            outputTexId: ?TexId,
            execution: ComputeIndirectExec,
            compute: ShaderInf,
            bufUses: []const BufferFill = &.{},
            texUses: []const TextureFill = &.{},
        },
    ) PassInstance {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.compute.typ == .comp);

        var pass = PassInstance{
            .mainOutputTex = inf.outputTexId,
            .execution = .{ .computeIndirect = inf.execution },
        };
        pass.name.fill(inf.name);

        pass.shaderIds.appendAssumeCapacity(inf.compute.id);

        pass.bufUses.appendSliceAssumeCapacity(inf.bufUses);
        pass.texUses.appendSliceAssumeCapacity(inf.texUses);

        return pass;
    }

    pub fn TaskMeshIndirect(
        inf: struct {
            name: []const u8,
            outputTexId: ?TexId,
            execution: TaskOrMeshIndirectExec,
            task: ShaderInf,
            mesh: ShaderInf,
            fragment: ShaderInf,
            bufUses: []const BufferFill = &.{},
            texUses: []const TextureFill = &.{},
            colorAtts: []const AttachmentFill = &.{},
            depthAtt: ?AttachmentFill = null,
            stencilAtt: ?AttachmentFill = null,
            renderState: RenderState = .{},
        },
    ) PassInstance {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.task.typ == .task);
        std.debug.assert(inf.mesh.typ == .meshWithTask);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = PassInstance{
            .mainOutputTex = inf.outputTexId,
            .execution = .{ .taskOrMeshIndirect = inf.execution },
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };
        pass.name.fill(inf.name);

        pass.shaderIds.appendAssumeCapacity(inf.task.id);
        pass.shaderIds.appendAssumeCapacity(inf.mesh.id);
        pass.shaderIds.appendAssumeCapacity(inf.fragment.id);

        pass.bufUses.appendSliceAssumeCapacity(inf.bufUses);
        pass.texUses.appendSliceAssumeCapacity(inf.texUses);
        pass.colorAtts.appendSliceAssumeCapacity(inf.colorAtts);

        return pass;
    }

    pub fn Mesh(
        inf: struct {
            name: []const u8,
            outputTexId: ?TexId,
            execution: TaskOrMeshExec,
            mesh: ShaderInf,
            fragment: ShaderInf,
            bufUses: []const BufferFill = &.{},
            texUses: []const TextureFill = &.{},
            colorAtts: []const AttachmentFill = &.{},
            depthAtt: ?AttachmentFill = null,
            stencilAtt: ?AttachmentFill = null,
            renderState: RenderState = .{},
        },
    ) PassInstance {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.mesh.typ == .meshNoTask);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = PassInstance{
            .mainOutputTex = inf.outputTexId,
            .execution = .{ .taskOrMesh = inf.execution },
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };
        pass.name.fill(inf.name);

        pass.shaderIds.appendAssumeCapacity(inf.mesh.id);
        pass.shaderIds.appendAssumeCapacity(inf.fragment.id);

        pass.bufUses.appendSliceAssumeCapacity(inf.bufUses);
        pass.texUses.appendSliceAssumeCapacity(inf.texUses);
        pass.colorAtts.appendSliceAssumeCapacity(inf.colorAtts);

        return pass;
    }

    pub fn MeshIndirect(
        inf: struct {
            name: []const u8,
            outputTexId: ?TexId,
            execution: TaskOrMeshIndirectExec,
            mesh: ShaderInf,
            fragment: ShaderInf,
            bufUses: []const BufferFill = &.{},
            texUses: []const TextureFill = &.{},
            colorAtts: []const AttachmentFill = &.{},
            depthAtt: ?AttachmentFill = null,
            stencilAtt: ?AttachmentFill = null,
            renderState: RenderState = .{},
        },
    ) PassInstance {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.mesh.typ == .meshNoTask);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = PassInstance{
            .mainOutputTex = inf.outputTexId,
            .execution = .{ .taskOrMeshIndirect = inf.execution },
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };
        pass.name.fill(inf.name);

        pass.shaderIds.appendAssumeCapacity(inf.mesh.id);
        pass.shaderIds.appendAssumeCapacity(inf.fragment.id);

        pass.bufUses.appendSliceAssumeCapacity(inf.bufUses);
        pass.texUses.appendSliceAssumeCapacity(inf.texUses);
        pass.colorAtts.appendSliceAssumeCapacity(inf.colorAtts);

        return pass;
    }

    pub fn getName(self: *const PassInstance) []const u8 {
        return self.name.get();
    }

    pub fn getShaderIds(self: *const PassInstance) []const ShaderId {
        return self.shaderIds.constSlice();
    }

    pub fn getBufUses(self: *const PassInstance) []const BufferFill {
        return self.bufUses.constSlice();
    }

    pub fn getTexUses(self: *const PassInstance) []const TextureFill {
        return self.texUses.constSlice();
    }

    pub fn getColorAtts(self: *const PassInstance) []const AttachmentFill {
        return self.colorAtts.constSlice();
    }

    pub fn getVertexBufUse(self: *const PassInstance) []const VertexBufferFill {
        return self.vertexBuffers.constSlice();
    }

    pub fn getMainTexId(self: *const PassInstance) ?TexId {
        return switch (self.execution) {
            .taskOrMesh => self.mainOutputTex,
            .taskOrMeshIndirect => self.mainOutputTex,
            .graphics => self.mainOutputTex,
            .compute => self.mainOutputTex,
            .computeIndirect => null,
        };
    }
};
