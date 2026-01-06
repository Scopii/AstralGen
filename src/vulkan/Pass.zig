const ResourceState = @import("../vulkan/RenderGraph.zig").ResourceState;
const ResourceSlot = @import("resources/Resource.zig").ResourceSlot;
const vh = @import("../vulkan/Helpers.zig");

pub const Pass = struct {
    shaderIds: []const u8,
    bufUses: []const BufferUse = &.{},
    texUses: []const TextureUse = &.{},
    passTyp: PassType,

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
        mainTexId: u32,
        workgroups: Dispatch,
    };

    const TaskOrMeshData = struct {
        mainTexId: u32,
        colorAtts: []const Attachment,
        depthAtt: ?Attachment = null,
        stencilAtt: ?Attachment = null,
        workgroups: Dispatch,
    };

    const GraphicsData = struct {
        mainTexId: u32,
        colorAtts: []const Attachment,
        depthAtt: ?Attachment = null,
        stencilAtt: ?Attachment = null,
        draw: struct { vertices: u32, instances: u32 } = .{ .vertices = 3, .instances = 1 },
    };

    pub fn ComputeOnImage(data: computeOnTexData) Pass.PassType {
        return .{ .computeOnTex = data };
    }

    pub fn createCompute(data: ComputeData) Pass.PassType {
        return .{ .compute = .{ .workgroups = data.workgroups } };
    }

    pub fn Graphics(data: GraphicsData) Pass.PassType {
        return .{ .graphics = data };
    }

    pub fn TaskOrMesh(data: TaskOrMeshData) Pass.PassType {
        return .{ .taskOrMesh = data };
    }

    pub fn getColorAtts(self: *const Pass) []const Attachment {
        return switch (self.passTyp) {
            .graphics => |g| g.colorAtts,
            .taskOrMesh => |t| t.colorAtts,
            .compute, .computeOnTex => &[_]Attachment{},
        };
    }

    pub fn getDepthAtt(self: *const Pass) ?Attachment {
        return switch (self.passTyp) {
            .graphics => |g| g.depthAtt,
            .taskOrMesh => |t| t.depthAtt,
            .compute, .computeOnTex => null,
        };
    }

    pub fn getStencilAtt(self: *const Pass) ?Attachment {
        return switch (self.passTyp) {
            .graphics => |g| g.stencilAtt,
            .taskOrMesh => |t| t.stencilAtt,
            .compute, .computeOnTex => null,
        };
    }

    pub const Dispatch = struct { x: u32, y: u32, z: u32 };
};

pub const Attachment = struct {
    texId: u32,
    stage: vh.PipeStage = .TopOfPipe,
    access: vh.PipeAccess = .None,
    layout: vh.ImageLayout = .General,
    clear: bool,

    pub fn getNeededState(self: *const Attachment) ResourceState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }

    pub fn create(id: u32, stage: vh.PipeStage, access: vh.PipeAccess, clear: bool) Attachment {
        return .{ .texId = id, .stage = stage, .access = access, .layout = .Attachment, .clear = clear };
    }
};

pub const TextureUse = struct {
    texId: u32,
    stage: vh.PipeStage = .TopOfPipe,
    access: vh.PipeAccess = .None,
    layout: vh.ImageLayout = .General,
    shaderSlot: ?u8 = null,

    pub fn getNeededState(self: *const TextureUse) ResourceState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }

    pub fn create(id: u32, stage: vh.PipeStage, access: vh.PipeAccess, layout: vh.ImageLayout, shaderSlot: ?u8) TextureUse {
        return .{ .texId = id, .stage = stage, .access = access, .layout = layout, .shaderSlot = shaderSlot };
    }
};

pub const BufferUse = struct {
    bufId: u32,
    stage: vh.PipeStage = .TopOfPipe,
    access: vh.PipeAccess = .None,
    shaderSlot: ?u8 = null,

    pub fn getNeededState(self: *const BufferUse) ResourceState {
        return .{ .stage = self.stage, .access = self.access, .layout = .General };
    }

    pub fn create(bufId: u32, stage: vh.PipeStage, access: vh.PipeAccess, shaderSlot: ?u8) BufferUse {
        return .{ .bufId = bufId, .stage = stage, .access = access, .shaderSlot = shaderSlot };
    }
};
