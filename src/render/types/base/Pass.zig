const ShaderId = @import("../../../shader/ShaderSys.zig").ShaderId;
const ShaderInf = @import("../../../shader/ShaderInf.zig").ShaderInf;
const RenderState = @import("../base/RenderState.zig").RenderState;
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
    pass: Pass,
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

pub const Pass = struct {
    name: []const u8,
    execution: PassExecution,

    shaderCount: u8 = 0,
    shaderIds: [3]ShaderId = undefined,

    bufCount: u8 = 0,
    bufUses: [14]BufferUse = undefined,

    texCount: u8 = 0,
    texUses: [14]TextureUse = undefined,

    renderState: RenderState = .{},

    colorAttCount: u8 = 0,
    colorAtts: [8]Attachment = undefined,
    depthAtt: ?Attachment = null,
    stencilAtt: ?Attachment = null,

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
            colorAtts: []const Attachment = &.{},
            depthAtt: ?Attachment = null,
            stencilAtt: ?Attachment = null,
            renderState: RenderState = .{},
        },
    ) Pass {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.vertex.typ == .vert);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = Pass{
            .name = inf.name,
            .execution = inf.execution,
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };

        pass.shaderIds[0] = inf.vertex.id;
        pass.shaderIds[1] = inf.fragment.id;
        pass.shaderCount = 2;

        @memcpy(pass.bufUses[0..inf.bufUses.len], inf.bufUses);
        pass.bufCount = @intCast(inf.bufUses.len);

        @memcpy(pass.texUses[0..inf.texUses.len], inf.texUses);
        pass.texCount = @intCast(inf.texUses.len);

        @memcpy(pass.colorAtts[0..inf.colorAtts.len], inf.colorAtts);
        pass.colorAttCount = @intCast(inf.colorAtts.len);

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
    ) Pass {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.compute.typ == .comp);

        var pass = Pass{
            .name = inf.name,
            .execution = .{ .compute = inf.execution },
        };

        pass.shaderIds[0] = inf.compute.id;
        pass.shaderCount = 1;

        @memcpy(pass.bufUses[0..inf.bufUses.len], inf.bufUses);
        pass.bufCount = @intCast(inf.bufUses.len);

        @memcpy(pass.texUses[0..inf.texUses.len], inf.texUses);
        pass.texCount = @intCast(inf.texUses.len);

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
    ) Pass {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.compute.typ == .comp);

        var pass = Pass{
            .name = inf.name,
            .execution = .{ .computeOnImg = inf.execution },
        };

        pass.shaderIds[0] = inf.compute.id;
        pass.shaderCount = 1;

        @memcpy(pass.bufUses[0..inf.bufUses.len], inf.bufUses);
        pass.bufCount = @intCast(inf.bufUses.len);

        @memcpy(pass.texUses[0..inf.texUses.len], inf.texUses);
        pass.texCount = @intCast(inf.texUses.len);

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
            colorAtts: []const Attachment = &.{},
            depthAtt: ?Attachment = null,
            stencilAtt: ?Attachment = null,
            renderState: RenderState = .{},
        },
    ) Pass {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.task.typ == .task);
        std.debug.assert(inf.mesh.typ == .meshWithTask);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = Pass{
            .name = inf.name,
            .execution = inf.execution,
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };

        pass.shaderIds[0] = inf.task.id;
        pass.shaderIds[1] = inf.mesh.id;
        pass.shaderIds[2] = inf.fragment.id;
        pass.shaderCount = 3;

        @memcpy(pass.bufUses[0..inf.bufUses.len], inf.bufUses);
        pass.bufCount = @intCast(inf.bufUses.len);

        @memcpy(pass.texUses[0..inf.texUses.len], inf.texUses);
        pass.texCount = @intCast(inf.texUses.len);

        @memcpy(pass.colorAtts[0..inf.colorAtts.len], inf.colorAtts);
        pass.colorAttCount = @intCast(inf.colorAtts.len);

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
            colorAtts: []const Attachment = &.{},
            depthAtt: ?Attachment = null,
            stencilAtt: ?Attachment = null,
            renderState: RenderState = .{},
        },
    ) Pass {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.task.typ == .task);
        std.debug.assert(inf.mesh.typ == .meshWithTask);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = Pass{
            .name = inf.name,
            .execution = inf.execution,
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };

        pass.shaderIds[0] = inf.task.id;
        pass.shaderIds[1] = inf.mesh.id;
        pass.shaderIds[2] = inf.fragment.id;
        pass.shaderCount = 3;

        @memcpy(pass.bufUses[0..inf.bufUses.len], inf.bufUses);
        pass.bufCount = @intCast(inf.bufUses.len);

        @memcpy(pass.texUses[0..inf.texUses.len], inf.texUses);
        pass.texCount = @intCast(inf.texUses.len);

        @memcpy(pass.colorAtts[0..inf.colorAtts.len], inf.colorAtts);
        pass.colorAttCount = @intCast(inf.colorAtts.len);

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
            colorAtts: []const Attachment = &.{},
            depthAtt: ?Attachment = null,
            stencilAtt: ?Attachment = null,
            renderState: RenderState = .{},
        },
    ) Pass {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.mesh.typ == .meshNoTask);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = Pass{
            .name = inf.name,
            .execution = .{ .taskOrMesh = inf.execution },
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };

        pass.shaderIds[0] = inf.mesh.id;
        pass.shaderIds[1] = inf.fragment.id;
        pass.shaderCount = 2;

        @memcpy(pass.bufUses[0..inf.bufUses.len], inf.bufUses);
        pass.bufCount = @intCast(inf.bufUses.len);

        @memcpy(pass.texUses[0..inf.texUses.len], inf.texUses);
        pass.texCount = @intCast(inf.texUses.len);

        @memcpy(pass.colorAtts[0..inf.colorAtts.len], inf.colorAtts);
        pass.colorAttCount = @intCast(inf.colorAtts.len);

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
            colorAtts: []const Attachment = &.{},
            depthAtt: ?Attachment = null,
            stencilAtt: ?Attachment = null,
            renderState: RenderState = .{},
        },
    ) Pass {
        std.debug.assert(inf.bufUses.len + inf.texUses.len <= 14);
        std.debug.assert(inf.colorAtts.len <= 8);
        std.debug.assert(inf.mesh.typ == .meshNoTask);
        std.debug.assert(inf.fragment.typ == .frag);

        var pass = Pass{
            .name = inf.name,
            .execution = .{ .taskOrMeshIndirect = inf.execution },
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };

        pass.shaderIds[0] = inf.mesh.id;
        pass.shaderIds[1] = inf.fragment.id;
        pass.shaderCount = 2;

        @memcpy(pass.bufUses[0..inf.bufUses.len], inf.bufUses);
        pass.bufCount = @intCast(inf.bufUses.len);

        @memcpy(pass.texUses[0..inf.texUses.len], inf.texUses);
        pass.texCount = @intCast(inf.texUses.len);

        @memcpy(pass.colorAtts[0..inf.colorAtts.len], inf.colorAtts);
        pass.colorAttCount = @intCast(inf.colorAtts.len);

        return pass;
    }

    pub fn getShaderIds(self: *const Pass) []const ShaderId {
        return self.shaderIds[0..self.shaderCount];
    }

    pub fn getBufUses(self: *const Pass) []const BufferUse {
        return self.bufUses[0..self.bufCount];
    }

    pub fn getTexUses(self: *const Pass) []const TextureUse {
        return self.texUses[0..self.texCount];
    }

    pub fn getColorAtts(self: *const Pass) []const Attachment {
        return self.colorAtts[0..self.colorAttCount];
    }

    pub fn getMainTexId(self: *const Pass) ?TexId {
        return switch (self.execution) {
            .taskOrMesh => |taskOrMesh| taskOrMesh.mainTexId,
            .taskOrMeshIndirect => |taskOrMeshIndirect| taskOrMeshIndirect.mainTexId,
            .graphics => |graphics| graphics.mainTexId,
            .computeOnImg => |computeOnImg| computeOnImg.mainTexId,
            .compute => null,
        };
    }
};

pub const Attachment = struct {
    texId: TextureMeta.TexId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    clear: bool,

    pub fn init(id: TextureMeta.TexId, stage: vhE.PipeStage, access: vhE.PipeAccess, clear: bool) Attachment {
        return .{ .texId = id, .stage = stage, .access = access, .layout = .Attachment, .clear = clear };
    }

    pub fn getNeededState(self: *const Attachment) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};

pub const TextureUse = struct {
    texId: TextureMeta.TexId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    shaderSlot: ?u32 = null,

    pub fn init(id: TextureMeta.TexId, stage: vhE.PipeStage, access: vhE.PipeAccess, layout: vhE.ImageLayout, shaderSlot: ?u8) TextureUse {
        return .{ .texId = id, .stage = stage, .access = access, .layout = layout, .shaderSlot = if (shaderSlot) |slot| slot else null };
    }

    pub fn getNeededState(self: *const TextureUse) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};

pub const BufferUse = struct {
    bufId: BufferMeta.BufId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    shaderSlot: ?u32 = null,

    pub fn init(bufId: BufferMeta.BufId, stage: vhE.PipeStage, access: vhE.PipeAccess, shaderSlot: ?u8) BufferUse {
        return .{ .bufId = bufId, .stage = stage, .access = access, .shaderSlot = if (shaderSlot) |slot| slot else null };
    }

    pub fn getNeededState(self: *const BufferUse) Buffer.BufferState {
        return .{ .stage = self.stage, .access = self.access };
    }
};
