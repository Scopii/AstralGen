const ShaderId = @import("../../../shader/ShaderSys.zig").ShaderId;
const RenderState = @import("../base/RenderState.zig").RenderState;
const TextureMeta = @import("../res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../res/BufferMeta.zig").BufferMeta;
const Texture = @import("../res/Texture.zig").Texture;
const Buffer = @import("../res/Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");
const BufId = BufferMeta.BufId;
const TexId = TextureMeta.TexId;

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

    pub const Dispatch = struct { x: u32, y: u32, z: u32 };

    pub const PassExecution = union(enum) {
        compute: struct {
            workgroups: Dispatch,
        },
        computeOnImg: struct {
            workgroups: Dispatch,
            mainTexId: TexId,
        },
        taskOrMesh: struct {
            workgroups: Dispatch,
            mainTexId: TexId,
        },
        taskOrMeshIndirect: struct {
            workgroups: Dispatch,
            indirectBuf: BufId,
            indirectBufOffset: u64 = 0,
            mainTexId: TexId,
        },
        graphics: struct {
            vertices: u32 = 3,
            instances: u32 = 1,
            mainTexId: TexId,
        },
    };

    pub fn init(
        inf: struct {
            name: []const u8,
            execution: PassExecution,
            shaderIds: []const ShaderId,
            bufUses: []const BufferUse = &.{},
            texUses: []const TextureUse = &.{},
            colorAtts: []const Attachment = &.{},
            depthAtt: ?Attachment = null,
            stencilAtt: ?Attachment = null,
            renderState: RenderState = .{},
        },
    ) Pass {
        var pass = Pass{
            .name = inf.name,
            .execution = inf.execution,
            .depthAtt = inf.depthAtt,
            .stencilAtt = inf.stencilAtt,
            .renderState = inf.renderState,
        };

        pass.shaderIds[0..inf.shaderIds.len].* = inf.shaderIds[0..inf.shaderIds.len].*;
        pass.shaderCount = @intCast(inf.shaderIds.len);

        pass.bufUses[0..inf.bufUses.len].* = inf.bufUses[0..inf.bufUses.len].*;
        pass.bufCount = @intCast(inf.bufUses.len);

        pass.texUses[0..inf.texUses.len].* = inf.texUses[0..inf.texUses.len].*;
        pass.texCount = @intCast(inf.texUses.len);

        pass.colorAtts[0..inf.colorAtts.len].* = inf.colorAtts[0..inf.colorAtts.len].*;
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
            .computeOnImg => |computeOnImg| computeOnImg.mainTexId,
            .taskOrMesh => |taskOrMesh| taskOrMesh.mainTexId,
            .taskOrMeshIndirect => |taskOrMeshIndirect| taskOrMeshIndirect.mainTexId,
            .graphics => |graphics| graphics.mainTexId,
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
