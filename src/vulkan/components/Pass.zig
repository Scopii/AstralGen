const ShaderId = @import("../../configs/shaderConfig.zig").ShaderInf.ShaderId;
const TextureBase = @import("TextureBase.zig").TextureBase;
const Texture = @import("Texture.zig").Texture;
const Buffer = @import("Buffer.zig").Buffer;
const vh = @import("../systems/Helpers.zig");

pub const Pass = struct {
    shaderIds: []const ShaderId,
    bufUses: []const BufferUse = &.{},
    texUses: []const TextureUse = &.{},
    typ: PassType,

    pub const PassType = union(enum) {
        compute: Compute,
        computeOnTex: ComputeOnTex,
        taskOrMesh: TaskOrMesh,
        taskOrMeshIndirect: TaskOrMeshIndirect,
        graphics: Graphics,
    };

    const Compute = struct {
        workgroups: Dispatch,
    };

    const ComputeOnTex = struct {
        mainTexId: Texture.TexId,
        workgroups: Dispatch,
    };

    const TaskOrMesh = struct {
        mainTexId: Texture.TexId,
        colorAtts: []const Attachment,
        depthAtt: ?Attachment = null,
        stencilAtt: ?Attachment = null,
        workgroups: Dispatch,
    };

    const TaskOrMeshIndirect = struct {
        mainTexId: Texture.TexId,
        colorAtts: []const Attachment,
        depthAtt: ?Attachment = null,
        stencilAtt: ?Attachment = null,
        workgroups: Dispatch,
        indirectBuf: struct { id: Buffer.BufId, offset: u64 = 0 },
    };

    const Graphics = struct {
        mainTexId: Texture.TexId,
        colorAtts: []const Attachment,
        depthAtt: ?Attachment = null,
        stencilAtt: ?Attachment = null,
        draw: struct { vertices: u32, instances: u32 } = .{ .vertices = 3, .instances = 1 },
    };

    pub fn computeOnImage(data: ComputeOnTex) Pass.PassType {
        return .{ .computeOnTex = data };
    }

    pub fn compute(data: Compute) Pass.PassType {
        return .{ .compute = .{ .workgroups = data.workgroups } };
    }

    pub fn graphics(data: Graphics) Pass.PassType {
        return .{ .graphics = data };
    }

    pub fn taskOrMesh(data: TaskOrMesh) Pass.PassType {
        return .{ .taskOrMesh = data };
    }

    pub fn taskOrMeshIndirect(data: TaskOrMeshIndirect) Pass.PassType {
        return .{ .taskOrMeshIndirect = data };
    }

    pub fn getMainTexId(self: *const Pass) ?Texture.TexId {
        return switch (self.typ) {
            .taskOrMesh => |t| t.mainTexId,
            .graphics => |g| g.mainTexId,
            .taskOrMeshIndirect => |i| i.mainTexId,
            .computeOnTex => |c| c.mainTexId,
            .compute,
            => null,
        };
    }

    pub fn getColorAtts(self: *const Pass) []const Attachment {
        return switch (self.typ) {
            .taskOrMesh => |t| t.colorAtts,
            .graphics => |g| g.colorAtts,
            .taskOrMeshIndirect => |i| i.colorAtts,
            .compute, .computeOnTex => &[_]Attachment{},
        };
    }

    pub fn getDepthAtt(self: *const Pass) ?Attachment {
        return switch (self.typ) {
            .taskOrMesh => |t| t.depthAtt,
            .graphics => |g| g.depthAtt,
            .taskOrMeshIndirect => |i| i.depthAtt,
            .compute, .computeOnTex => null,
        };
    }

    pub fn getStencilAtt(self: *const Pass) ?Attachment {
        return switch (self.typ) {
            .taskOrMesh => |t| t.stencilAtt,
            .graphics => |g| g.stencilAtt,
            .taskOrMeshIndirect => |i| i.stencilAtt,
            .compute, .computeOnTex => null,
        };
    }

    pub const Dispatch = struct { x: u32, y: u32, z: u32 };
};

pub const Attachment = struct {
    texId: Texture.TexId,
    stage: vh.PipeStage = .TopOfPipe,
    access: vh.PipeAccess = .None,
    layout: vh.ImageLayout = .General,
    clear: bool,

    pub fn getNeededState(self: *const Attachment) TextureBase.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }

    pub fn init(id: Texture.TexId, stage: vh.PipeStage, access: vh.PipeAccess, clear: bool) Attachment {
        return .{ .texId = id, .stage = stage, .access = access, .layout = .Attachment, .clear = clear };
    }
};

pub const ShaderSlot = packed struct { val: u32 };

pub const TextureUse = struct {
    texId: Texture.TexId,
    stage: vh.PipeStage = .TopOfPipe,
    access: vh.PipeAccess = .None,
    layout: vh.ImageLayout = .General,
    shaderSlot: ?ShaderSlot = null,

    pub fn getNeededState(self: *const TextureUse) TextureBase.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }

    pub fn init(id: Texture.TexId, stage: vh.PipeStage, access: vh.PipeAccess, layout: vh.ImageLayout, shaderSlot: ?u8) TextureUse {
        return .{ .texId = id, .stage = stage, .access = access, .layout = layout, .shaderSlot = if (shaderSlot) |slot| .{ .val = slot } else null };
    }
};

pub const BufferUse = struct {
    bufId: Buffer.BufId,
    stage: vh.PipeStage = .TopOfPipe,
    access: vh.PipeAccess = .None,
    shaderSlot: ?ShaderSlot = null,

    pub fn getNeededState(self: *const BufferUse) Buffer.BufferState {
        return .{ .stage = self.stage, .access = self.access};
    }

    pub fn init(bufId: Buffer.BufId, stage: vh.PipeStage, access: vh.PipeAccess, shaderSlot: ?u8) BufferUse {
        return .{ .bufId = bufId, .stage = stage, .access = access, .shaderSlot = if (shaderSlot) |slot| .{ .val = slot } else null };
    }
};
