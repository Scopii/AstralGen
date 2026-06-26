const FixedList = @import("../../../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../../../frameBuild/components.zig").TexPassId;
const BufPassId = @import("../../../frameBuild/components.zig").BufPassId;
const VertexBufferUse = @import("VertexBufferUse.zig").VertexBufferUse;
const VertexAttribute = @import("VertexAttribute.zig").VertexAttribute;
const ShaderInf = @import("../../../shader/ShaderInf.zig").ShaderInf;
const IndexBufferUse = @import("IndexBufferUse.zig").IndexBufferUse;
const ShaderId = @import("../../../shader/ShaderSys.zig").ShaderId;
const RenderState = @import("../pass/RenderState.zig").RenderState;
const TexId = @import("../res/TextureMeta.zig").TextureMeta.TexId;
const AttachmentUse = @import("AttachmentUse.zig").AttachmentUse;
const TextureUse = @import("TextureUse.zig").TextureUse;
const BufferUse = @import("BufferUse.zig").BufferUse;
const std = @import("std");

const String = @import("../../../globalHelper.zig").String;

pub const Dispatch = struct { x: u32, y: u32, z: u32 };
pub const PassNode = struct { pass: PassDef, width: u32, height: u32 };

pub const ComputeExec = struct { workgroups: Dispatch, outputTexDispatch: bool };
pub const ComputeIndirectExec = struct { indirectBuf: BufPassId, indirectBufOffset: u64 = 0 };
pub const TaskOrMeshExec = struct { workgroups: Dispatch };
pub const TaskOrMeshIndirectExec = struct { workgroups: Dispatch, indirectBuf: BufPassId, indirectBufOffset: u64 = 0 };
pub const GraphicsExec = struct { vertices: u32, instances: u32, indexCount: u32 };

pub const PassDef = struct {
    name: String(30, "PASS_NAME_MISSING") = .{},
    execution: PassExecution,
    mainOutputTex: ?TexPassId,

    // All passes
    shaderIds: FixedList(ShaderId, 3) = .{},
    bufUses: FixedList(BufferUse, 14) = .{},
    texUses: FixedList(TextureUse, 14) = .{},

    // All Graphics Passes
    renderState: RenderState = .{},
    colorAtts: FixedList(AttachmentUse, 8) = .{},
    depthAtt: ?AttachmentUse = null,
    stencilAtt: ?AttachmentUse = null,

    // Vertex Passes Only
    vertexBuffers: FixedList(VertexBufferUse, 4) = .{},
    indexBuffer: ?IndexBufferUse = null,
    vertexAttributes: FixedList(VertexAttribute, 16) = .{},

    pub const PassExecution = union(enum) {
        compute: ComputeExec,
        computeIndirect: ComputeIndirectExec,
        taskOrMesh: TaskOrMeshExec,
        taskOrMeshIndirect: TaskOrMeshIndirectExec,
        graphics: GraphicsExec,
    };

    pub fn Graphics(
        inf: struct {
            name: []const u8,
            outputTexId: ?TexPassId,
            execution: GraphicsExec,
            vertex: ShaderInf,
            fragment: ShaderInf,
            bufUses: []const BufferUse = &.{},
            texUses: []const TextureUse = &.{},
            colorAtts: []const AttachmentUse = &.{},
            depthAtt: ?AttachmentUse = null,
            stencilAtt: ?AttachmentUse = null,
            renderState: RenderState = .{},
            vertexBuffers: []const VertexBufferUse = &.{},
            indexBuffer: ?IndexBufferUse = null,
            vertexAttributes: []const VertexAttribute = &.{},
        },
    ) PassDef {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.vertex.typ == .vert);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = PassDef{
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
            outputTexId: ?TexPassId,
            execution: ComputeExec,
            compute: ShaderInf,
            bufUses: []const BufferUse = &.{},
            texUses: []const TextureUse = &.{},
        },
    ) PassDef {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.compute.typ == .comp);

        var pass = PassDef{
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
            outputTexId: ?TexPassId,
            execution: ComputeIndirectExec,
            compute: ShaderInf,
            bufUses: []const BufferUse = &.{},
            texUses: []const TextureUse = &.{},
        },
    ) PassDef {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.compute.typ == .comp);

        var pass = PassDef{
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
            outputTexId: ?TexPassId,
            execution: TaskOrMeshIndirectExec,
            task: ShaderInf,
            mesh: ShaderInf,
            fragment: ShaderInf,
            bufUses: []const BufferUse = &.{},
            texUses: []const TextureUse = &.{},
            colorAtts: []const AttachmentUse = &.{},
            depthAtt: ?AttachmentUse = null,
            stencilAtt: ?AttachmentUse = null,
            renderState: RenderState = .{},
        },
    ) PassDef {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.task.typ == .task);
        std.debug.assert(inf.mesh.typ == .meshWithTask);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = PassDef{
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
            outputTexId: ?TexPassId,
            execution: TaskOrMeshExec,
            mesh: ShaderInf,
            fragment: ShaderInf,
            bufUses: []const BufferUse = &.{},
            texUses: []const TextureUse = &.{},
            colorAtts: []const AttachmentUse = &.{},
            depthAtt: ?AttachmentUse = null,
            stencilAtt: ?AttachmentUse = null,
            renderState: RenderState = .{},
        },
    ) PassDef {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.mesh.typ == .meshNoTask);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = PassDef{
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
            outputTexId: ?TexPassId,
            execution: TaskOrMeshIndirectExec,
            mesh: ShaderInf,
            fragment: ShaderInf,
            bufUses: []const BufferUse = &.{},
            texUses: []const TextureUse = &.{},
            colorAtts: []const AttachmentUse = &.{},
            depthAtt: ?AttachmentUse = null,
            stencilAtt: ?AttachmentUse = null,
            renderState: RenderState = .{},
        },
    ) PassDef {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.mesh.typ == .meshNoTask);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = PassDef{
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

    pub fn getName(self: *const PassDef) []const u8 {
        return self.name.get();
    }

    pub fn getShaderIds(self: *const PassDef) []const ShaderId {
        return self.shaderIds.constSlice();
    }

    pub fn getBufUses(self: *const PassDef) []const BufferUse {
        return self.bufUses.constSlice();
    }

    pub fn getTexUses(self: *const PassDef) []const TextureUse {
        return self.texUses.constSlice();
    }

    pub fn getColorAtts(self: *const PassDef) []const AttachmentUse {
        return self.colorAtts.constSlice();
    }

    pub fn getVertexBufUse(self: *const PassDef) []const VertexBufferUse {
        return self.vertexBuffers.constSlice();
    }

    pub fn getMainTexId(self: *const PassDef) ?TexPassId {
        return switch (self.execution) {
            .taskOrMesh => self.mainOutputTex,
            .taskOrMeshIndirect => self.mainOutputTex,
            .graphics => self.mainOutputTex,
            .compute => self.mainOutputTex,
            .computeIndirect => null,
        };
    }
};
