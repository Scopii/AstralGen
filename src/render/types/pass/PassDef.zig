const ShaderId = @import("../../../shader/ShaderSys.zig").ShaderId;
const ShaderInf = @import("../../../shader/ShaderInf.zig").ShaderInf;
const RenderState = @import("../pass/RenderState.zig").RenderState;
const TextureMeta = @import("../res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../res/BufferMeta.zig").BufferMeta;
const Texture = @import("../res/Texture.zig").Texture;
const Buffer = @import("../res/Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");
const BufId = BufferMeta.BufId;
const TexId = TextureMeta.TexId;
const WindowId = @import("../../../window/Window.zig").Window.WindowId;
const ViewportId = @import("../../../viewport/ViewportSys.zig").ViewportId;
const std = @import("std");
const AttachmentUse = @import("Attachment.zig").AttachmentUse;
const BufferUse = @import("BufferUse.zig").BufferUse;
const TextureUse = @import("TextureUse.zig").TextureUse;
const FixedList = @import("../../../.structures/FixedList.zig").FixedList;

pub const Dispatch = struct { x: u32, y: u32, z: u32 };

pub const ComputeExec = struct {
    workgroups: Dispatch,
};

pub const ComputeOnImgExec = struct {
    workgroups: Dispatch,
    mainTexId: TexId,
};

pub const TaskOrMeshExec = struct {
    workgroups: Dispatch,
    mainTexId: TexId,
};

pub const TaskOrMeshIndirectExec = struct {
    workgroups: Dispatch,
    indirectBuf: BufId,
    indirectBufOffset: u64 = 0,
    mainTexId: TexId,
};

pub const GraphicsExec = struct {
    vertices: u32 = 3,
    instances: u32 = 1,
    mainTexId: TexId,
};

pub const RenderNode = union(enum) {
    viewportBlit: ViewportBlit,
    passNode: struct { pass: PassDef, width: u32, height: u32 },
};

pub const ViewportBlit = struct {
    name: []const u8,
    srcTexId: TexId,
    dstWindowId: WindowId,
    viewWidth: u32,
    viewHeight: u32,
    viewOffsetX: i32,
    viewOffsetY: i32,
};

pub const PassDef = struct {
    name: []const u8,
    execution: PassExecution,

    shaderIds: FixedList(ShaderId, 3) = .{},
    bufUses: FixedList(BufferUse, 14) = .{},
    texUses: FixedList(TextureUse, 14) = .{},

    renderState: RenderState = .{},
    colorAtts: FixedList(AttachmentUse, 8) = .{},
    depthAtt: ?AttachmentUse = null,
    stencilAtt: ?AttachmentUse = null,

    pub const PassExecution = union(enum) {
        compute: ComputeExec,
        computeOnImg: ComputeOnImgExec,
        taskOrMesh: TaskOrMeshExec,
        taskOrMeshIndirect: TaskOrMeshIndirectExec,
        graphics: GraphicsExec,
    };

    pub fn Graphics(
        inf: struct {
            name: []const u8,
            execution: PassExecution,
            vertex: ShaderInf,
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
        std.debug.assert(inf.vertex.typ == .vert);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = PassDef{
            .name = inf.name,
            .execution = inf.execution,
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };

        pass.shaderIds.append(inf.vertex.id);
        pass.shaderIds.append(inf.fragment.id);

        pass.bufUses.appendSliceAssumeCapacity(inf.bufUses);
        pass.texUses.appendSliceAssumeCapacity(inf.texUses);
        pass.colorAtts.appendSliceAssumeCapacity(inf.colorAtts);

        return pass;
    }

    pub fn Compute(
        inf: struct {
            name: []const u8,
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
            .execution = .{ .compute = inf.execution },
        };

        pass.shaderIds.appendAssumeCapacity(inf.compute.id);

        pass.bufUses.appendSliceAssumeCapacity(inf.bufUses);
        pass.texUses.appendSliceAssumeCapacity(inf.texUses);

        return pass;
    }

    pub fn ComputeOnImg(
        inf: struct {
            name: []const u8,
            execution: ComputeOnImgExec,
            compute: ShaderInf,
            bufUses: []const BufferUse = &.{},
            texUses: []const TextureUse = &.{},
        },
    ) PassDef {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.compute.typ == .comp);

        var pass = PassDef{
            .name = inf.name,
            .execution = .{ .computeOnImg = inf.execution },
        };

        pass.shaderIds.appendAssumeCapacity(inf.compute.id);

        pass.bufUses.appendSliceAssumeCapacity(inf.bufUses);
        pass.texUses.appendSliceAssumeCapacity(inf.texUses);

        return pass;
    }

    pub fn TaskMesh(
        inf: struct {
            name: []const u8,
            execution: TaskOrMeshExec,
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

    pub fn TaskMeshIndirect(
        inf: struct {
            name: []const u8,
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
            name: []const u8,
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
            name: []const u8,
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

    pub fn getMainTexId(self: *const PassDef) ?TexId {
        return switch (self.execution) {
            .taskOrMesh => |taskOrMesh| taskOrMesh.mainTexId,
            .taskOrMeshIndirect => |taskOrMeshIndirect| taskOrMeshIndirect.mainTexId,
            .graphics => |graphics| graphics.mainTexId,
            .computeOnImg => |computeOnImg| computeOnImg.mainTexId,
            .compute => null,
        };
    }
};
