const ResourceState = @import("../vulkan/RenderGraph.zig").ResourceState;
const ve = @import("../vulkan/Helpers.zig");

pub const Pass = struct {
    shaderIds: []const u8,
    resUsages: []const ResourceUse = &.{},
    shaderUsages: []const ResourceUse,
    passType: PassType,

    pub const PassType = union(enum) {
        compute: struct {
            workgroups: Dispatch,
        },
        computeOnImage: struct {
            renderImgId: u32,
            workgroups: Dispatch,
        },
        taskOrMesh: struct {
            renderImgId: u32,
            colorAtts: []const Attachment,
            depthAtt: ?Attachment = null,
            stencilAtt: ?Attachment = null,
            workgroups: Dispatch,
        },
        graphics: struct {
            renderImgId: u32,
            colorAtts: []const Attachment,
            depthAtt: ?Attachment = null,
            stencilAtt: ?Attachment = null,
            vertexCount: u32 = 3,
            instanceCount: u32 = 1,
        },
    };

    pub fn createComputeOnImage(renderImgId: u32, groupX: u32, groupY: u32, groupZ: u32) Pass.PassType {
        return .{
            .computeOnImage = .{
                .renderImgId = renderImgId,
                .workgroups = .{ .x = groupX, .y = groupY, .z = groupZ },
            },
        };
    }

    pub fn createCompute(groupX: u32, groupY: u32, groupZ: u32) Pass.PassType {
        return .{
            .compute = .{
                .workgroups = .{ .x = groupX, .y = groupY, .z = groupZ },
            },
        };
    }

    pub fn createGraphics(renderImgId: u32, vertexCount: u32, instanceCount: u32, colorAtts: []const Attachment, depthAtt: ?Attachment, stencilAtt: ?Attachment) Pass.PassType {
        return .{
            .graphics = .{
                .renderImgId = renderImgId,
                .vertexCount = vertexCount,
                .instanceCount = instanceCount,
                .colorAtts = colorAtts,
                .depthAtt = depthAtt,
                .stencilAtt = stencilAtt,
            },
        };
    }

    pub fn getColorAtts(self: *const Pass) []const Attachment {
        return switch (self.passType) {
            .graphics => |g| g.colorAtts,
            .taskOrMesh => |t| t.colorAtts,
            .compute, .computeOnImage => &[_]Attachment{},
        };
    }

    pub fn getDepthAtt(self: *const Pass) ?Attachment {
        return switch (self.passType) {
            .graphics => |g| g.depthAtt,
            .taskOrMesh => |t| t.depthAtt,
            .compute, .computeOnImage => null,
        };
    }

    pub fn getStencilAtt(self: *const Pass) ?Attachment {
        return switch (self.passType) {
            .graphics => |g| g.stencilAtt,
            .taskOrMesh => |t| t.stencilAtt,
            .compute, .computeOnImage => null,
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
