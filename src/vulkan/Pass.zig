const ResourceState = @import("../vulkan/RenderGraph.zig").ResourceState;
const ve = @import("../vulkan/Helpers.zig");

pub const Pass = struct {
    shaderIds: []const u8,
    resUsages: []const ResourceUse = &.{},
    shaderUsages: []const ResourceUse,
    passType: PassType,

    pub const PassType = union(enum) {
        compute: ComputeData,
        computeOnImg: ComputeOnImgData,
        taskOrMesh: TaskOrMeshData,
        graphics: GraphicsData,
    };

    const ComputeData = struct {
        workgroups: Dispatch,
    };

    const ComputeOnImgData = struct {
        mainImgId: u32,
        workgroups: Dispatch,
    };

    const TaskOrMeshData = struct {
        mainImgId: u32,
        colorAtts: []const Attachment,
        depthAtt: ?Attachment = null,
        stencilAtt: ?Attachment = null,
        workgroups: Dispatch,
    };

    const GraphicsData = struct {
        mainImgId: u32,
        colorAtts: []const Attachment,
        depthAtt: ?Attachment = null,
        stencilAtt: ?Attachment = null,
        draw: struct { vertices: u32, instances: u32} = .{.vertices = 3, .instances = 1},
    };

    pub fn createComputeOnImage(data: ComputeOnImgData) Pass.PassType {
        return .{ .computeOnImg = data };
    }

    pub fn createCompute(data: ComputeData) Pass.PassType {
        return .{ .compute = .{ .workgroups = data.workgroups } };
    }

    pub fn createGraphics(data: GraphicsData) Pass.PassType {
        return .{ .graphics = data };
    }

    pub fn createTaskOrMesh(data: TaskOrMeshData) Pass.PassType {
        return .{ .taskOrMesh = data };
    }

    pub fn getColorAtts(self: *const Pass) []const Attachment {
        return switch (self.passType) {
            .graphics => |g| g.colorAtts,
            .taskOrMesh => |t| t.colorAtts,
            .compute, .computeOnImg => &[_]Attachment{},
        };
    }

    pub fn getDepthAtt(self: *const Pass) ?Attachment {
        return switch (self.passType) {
            .graphics => |g| g.depthAtt,
            .taskOrMesh => |t| t.depthAtt,
            .compute, .computeOnImg => null,
        };
    }

    pub fn getStencilAtt(self: *const Pass) ?Attachment {
        return switch (self.passType) {
            .graphics => |g| g.stencilAtt,
            .taskOrMesh => |t| t.stencilAtt,
            .compute, .computeOnImg => null,
        };
    }

    pub const Dispatch = struct { x: u32, y: u32, z: u32 };
};

pub const Attachment = struct {
    id: u32,
    stage: ve.PipeStage = .TopOfPipe,
    access: ve.PipeAccess = .None,
    layout: ve.ImageLayout = .General,
    clear: bool,

    pub fn getNeededState(self: *const Attachment) ResourceState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }

    pub fn create(id: u32, stage: ve.PipeStage, access: ve.PipeAccess, clear: bool) Attachment {
        return .{ .id = id, .stage = stage, .access = access, .layout = .Attachment, .clear = clear };
    }
};

pub const ResourceUse = struct {
    id: u32,
    stage: ve.PipeStage = .TopOfPipe,
    access: ve.PipeAccess = .None,
    layout: ve.ImageLayout = .General,

    pub fn getNeededState(self: *const ResourceUse) ResourceState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }

    pub fn create(id: u32, stage: ve.PipeStage, access: ve.PipeAccess, layout: ve.ImageLayout) ResourceUse {
        return .{ .id = id, .stage = stage, .access = access, .layout = layout };
    }
};
