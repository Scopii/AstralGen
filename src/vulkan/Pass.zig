const ResourceState = @import("../vulkan/RenderGraph.zig").ResourceState;
const ResourceSlot = @import("resources/Resource.zig").ResourceSlot;
const Texture = @import("resources/Texture.zig").Texture;
const Buffer = @import("resources/Buffer.zig").Buffer;
const vh = @import("../vulkan/Helpers.zig");
const ShaderId = @import("../configs/shaderConfig.zig").ShaderInf.ShaderId;

pub const Pass = struct {
    shaderIds: []const ShaderId,
    bufUses: []const BufferUse = &.{},
    texUses: []const TextureUse = &.{},
    typ: PassType,

    pub const PassType = union(enum) {
        compute: ComputeData,
        computeOnTex: computeOnTexData,
        taskOrMesh: TaskOrMeshData,
        graphics: GraphicsData,
    };

    const ComputeData = struct {
        workgroups: Dispatch,
    };

    const computeOnTexData = struct {
        mainTexId: Texture.TexId,
        workgroups: Dispatch,
    };

    const TaskOrMeshData = struct {
        mainTexId: Texture.TexId,
        colorAtts: []const Attachment,
        depthAtt: ?Attachment = null,
        stencilAtt: ?Attachment = null,
        workgroups: Dispatch,
    };

    const GraphicsData = struct {
        mainTexId: Texture.TexId,
        colorAtts: []const Attachment,
        depthAtt: ?Attachment = null,
        stencilAtt: ?Attachment = null,
        draw: struct { vertices: u32, instances: u32 } = .{ .vertices = 3, .instances = 1 },
    };

    pub fn ComputeOnImage(data: computeOnTexData) Pass.PassType {
        return .{ .computeOnTex = data };
    }

    pub fn Compute(data: ComputeData) Pass.PassType {
        return .{ .compute = .{ .workgroups = data.workgroups } };
    }

    pub fn Graphics(data: GraphicsData) Pass.PassType {
        return .{ .graphics = data };
    }

    pub fn TaskOrMesh(data: TaskOrMeshData) Pass.PassType {
        return .{ .taskOrMesh = data };
    }

    pub fn getColorAtts(self: *const Pass) []const Attachment {
        return switch (self.typ) {
            .taskOrMesh => |t| t.colorAtts,
            .graphics => |g| g.colorAtts,

            .compute, .computeOnTex => &[_]Attachment{},
        };
    }

    pub fn getDepthAtt(self: *const Pass) ?Attachment {
        return switch (self.typ) {
            .taskOrMesh => |t| t.depthAtt,
            .graphics => |g| g.depthAtt,
            .compute, .computeOnTex => null,
        };
    }

    pub fn getStencilAtt(self: *const Pass) ?Attachment {
        return switch (self.typ) {
            .taskOrMesh => |t| t.stencilAtt,
            .graphics => |g| g.stencilAtt,
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

    pub fn getNeededState(self: *const Attachment) ResourceState {
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

    pub fn getNeededState(self: *const TextureUse) ResourceState {
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

    pub fn getNeededState(self: *const BufferUse) ResourceState {
        return .{ .stage = self.stage, .access = self.access, .layout = .General };
    }

    pub fn init(bufId: Buffer.BufId, stage: vh.PipeStage, access: vh.PipeAccess, shaderSlot: ?u8) BufferUse {
        return .{ .bufId = bufId, .stage = stage, .access = access, .shaderSlot = if (shaderSlot) |slot| .{ .val = slot } else null };
    }
};
