const FixedList = @import("../../../.structures/FixedList.zig").FixedList;
const TextureEnum = @import("../../../frameBuild/enums.zig").TextureEnum;
const BufferEnum = @import("../../../frameBuild/enums.zig").BufferEnum;
const VertexBufferUse = @import("VertexBufferUse.zig").VertexBufferUse;
const VertexAttribute = @import("VertexAttribute.zig").VertexAttribute;
const WindowId = @import("../../../window/Window.zig").Window.WindowId;
const ShaderInf = @import("../../../shader/ShaderInf.zig").ShaderInf;
const IndexBufferUse = @import("IndexBufferUse.zig").IndexBufferUse;
const PassEnum = @import("../../../frameBuild/enums.zig").PassEnum;
const ShaderId = @import("../../../shader/ShaderSys.zig").ShaderId;
const RenderState = @import("../pass/RenderState.zig").RenderState;
const TexId = @import("../res/TextureMeta.zig").TextureMeta.TexId;
const AttachmentUse = @import("AttachmentUse.zig").AttachmentUse;
const BufId = @import("../res/BufferMeta.zig").BufferMeta.BufId;
const TextureUse = @import("TextureUse.zig").TextureUse;
const BufferUse = @import("BufferUse.zig").BufferUse;
const std = @import("std");

pub const Dispatch = struct { x: u32, y: u32, z: u32 };

pub const ComputeExec = struct {
    workgroups: Dispatch,
    outputTexDispatch: bool,
};

pub const ComputeIndirectExec = struct {
    indirectBuf: BufferEnum,
    indirectBufOffset: u64 = 0,
};

pub const TaskOrMeshExec = struct {
    workgroups: Dispatch,
};

pub const TaskOrMeshIndirectExec = struct {
    workgroups: Dispatch,
    indirectBuf: BufferEnum,
    indirectBufOffset: u64 = 0,
};

pub const GraphicsExec = struct {
    vertices: u32,
    instances: u32,
    indexCount: u32,
};

pub const PassNode = struct { pass: PassDef, width: u32, height: u32 };

pub const RenderNode = union(enum) {
    viewportBlit: ViewportBlit,
    passNode: PassNode,
    uiNode: UiNode,
    compositeNode: CompositeNode,
    clearBuffer: BufId,
    clearTexture: TexId,
    barrierBakeClears: void,
};

pub const CompositeNode = struct {
    name: []const u8,
    pass: PassEnum,
    windowId: WindowId,
    srcTexEnum: ?TextureEnum = null,
    viewWidth: u32,
    viewHeight: u32,
    viewOffsetX: i32,
    viewOffsetY: i32,
    opacity: f32,
    stretch: bool,
};

pub const UiNode = struct {
    name: []const u8,
    windowId: WindowId,
    displayPos: [2]f32,
    displaySize: [2]f32,
    drawList: []const UiDraw,

    pub const UiDraw = struct {
        clipRect: [4]f32,
        texEnum: TextureEnum,
        vtxOffset: i32,
        idxOffset: u32,
        elemCount: u32,
    };
};

pub const ViewportBlit = struct {
    name: []const u8,
    pass: PassEnum,
    srcTexEnum: ?TextureEnum = null,
    dstWindowId: WindowId,
    viewWidth: u32,
    viewHeight: u32,
    viewOffsetX: i32,
    viewOffsetY: i32,
};

pub const PassDef = struct {
    name: PassEnum,
    execution: PassExecution,
    mainOutputTex: ?TextureEnum,

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
            name: PassEnum,
            outputTexId: ?TextureEnum,
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
            .name = inf.name,
            .mainOutputTex = inf.outputTexId,
            .execution = .{ .graphics = inf.execution },
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };

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
            name: PassEnum,
            outputTexId: ?TextureEnum,
            execution: ComputeExec,
            compute: ShaderInf,
            bufUses: []const BufferUse = &.{},
            texUses: []const TextureUse = &.{},
        },
    ) PassDef {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.compute.typ == .comp);

        var pass = PassDef{
            .name = inf.name,
            .mainOutputTex = inf.outputTexId,
            .execution = .{ .compute = inf.execution },
        };

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
            bufUses: []const BufferUse = &.{},
            texUses: []const TextureUse = &.{},
        },
    ) PassDef {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.compute.typ == .comp);

        var pass = PassDef{
            .name = inf.name,
            .mainOutputTex = inf.outputTexId,
            .execution = .{ .compute = inf.execution },
        };

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
            .name = inf.name,
            .mainOutputTex = inf.outputTexId,
            .execution = inf.execution,
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };

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
            name: PassEnum,
            outputTexId: ?TextureEnum,
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
            .name = inf.name,
            .mainOutputTex = inf.outputTexId,
            .execution = .{ .taskOrMesh = inf.execution },
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };

        pass.shaderIds.appendAssumeCapacity(inf.mesh.id);
        pass.shaderIds.appendAssumeCapacity(inf.fragment.id);

        pass.bufUses.appendSliceAssumeCapacity(inf.bufUses);
        pass.texUses.appendSliceAssumeCapacity(inf.texUses);
        pass.colorAtts.appendSliceAssumeCapacity(inf.colorAtts);

        return pass;
    }

    pub fn MeshIndirect(
        inf: struct {
            name: PassEnum,
            outputTexId: ?TextureEnum,
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
            .name = inf.name,
            .mainOutputTex = inf.outputTexId,
            .execution = .{ .taskOrMeshIndirect = inf.execution },
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };

        pass.shaderIds.appendAssumeCapacity(inf.mesh.id);
        pass.shaderIds.appendAssumeCapacity(inf.fragment.id);

        pass.bufUses.appendSliceAssumeCapacity(inf.bufUses);
        pass.texUses.appendSliceAssumeCapacity(inf.texUses);
        pass.colorAtts.appendSliceAssumeCapacity(inf.colorAtts);

        return pass;
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

    pub fn getMainTexId(self: *const PassDef) ?TextureEnum {
        return switch (self.execution) {
            .taskOrMesh => self.mainOutputTex,
            .taskOrMeshIndirect => self.mainOutputTex,
            .graphics => self.mainOutputTex,
            .compute => self.mainOutputTex,
            .computeIndirect => null,
        };
    }
};
