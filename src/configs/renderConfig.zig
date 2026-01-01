const vk = @import("../modules/vk.zig").c;
const Object = @import("../ecs/EntityManager.zig").Object;
const CameraData = @import("../core/Camera.zig").CameraData;
const ResourceInf = @import("../vulkan/resources/Resource.zig").ResourceInf;
const ResourceState = @import("../vulkan/RenderGraph.zig").ResourceState;
const sc = @import("shaderConfig.zig");
const ve = @import("../vulkan/Helpers.zig");

// Rendering, Swapchains and Windows
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = vk.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const MAX_WINDOWS: u8 = 8;

pub const GPU_BUF_MAX = 16;
pub const GPU_IMG_MAX = 32;
pub const GPU_RESOURCE_MAX = GPU_BUF_MAX + GPU_IMG_MAX;

pub const RENDER_IMG_FORMAT = vk.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const RENDER_IMG_AUTO_RESIZE = true;
pub const RENDER_IMG_STRETCH = true; // Ignored on AUTO_RESIZE

pub const Pass = struct {
    shaderIds: []const u8,
    resUsages: []const ResourceUsage = &.{},
    shaderUsages: []const ResourceUsage,
    kind: PassKind,

    pub const PassKind = union(enum) {
        compute: struct {
            workgroups: Dispatch,
        },
        computeOnImage: struct {
            renderImgId: u32,
            workgroups: Dispatch,
        },
        taskOrMesh: struct {
            renderImgId: u32,
            colorAtts: []const AttachmentUsage,
            depthAtt: ?AttachmentUsage = null,
            stencilAtt: ?AttachmentUsage = null,
            workgroups: Dispatch,
        },
        graphics: struct {
            renderImgId: u32,
            colorAtts: []const AttachmentUsage,
            depthAtt: ?AttachmentUsage = null,
            stencilAtt: ?AttachmentUsage = null,
            vertexCount: u32 = 3,
            instanceCount: u32 = 1,
        },
    };
    pub const Dispatch = struct { x: u32, y: u32, z: u32 };
    // pub const AttachmentOld = struct { resUsageSlot: u8, clear: bool };
    pub const AttachmentUsage = struct {
        id: u32,
        stage: ve.PipeStage = .TopOfPipe,
        access: ve.PipeAccess = .None,
        layout: ve.ImageLayout = .General,
        clear: bool,

        pub fn getNeededState(self: *const AttachmentUsage) ResourceState {
            return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
        }
    };
    pub const ResourceUsage = struct {
        id: u32,
        stage: ve.PipeStage = .TopOfPipe,
        access: ve.PipeAccess = .None,
        layout: ve.ImageLayout = .General,

        pub fn getNeededState(self: *const ResourceUsage) ResourceState {
            return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
        }
    };
};

pub const STORAGE_IMG_BINDING = 0;
pub const STORAGE_BUF_BINDING = 1;
pub const SAMPLED_IMG_BINDING = 2;

pub const bindingRegistry: []const struct { binding: u32, descType: vk.VkDescriptorType, arrayLength: u32 } = &.{
    .{ .binding = STORAGE_IMG_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .arrayLength = GPU_IMG_MAX },
    .{ .binding = STORAGE_BUF_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .arrayLength = GPU_BUF_MAX },
    .{ .binding = SAMPLED_IMG_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, .arrayLength = GPU_IMG_MAX },
};

pub const objectSB = ResourceInf{ .id = 1, .memUse = .Gpu, .inf = .{ .bufInf = .{ .bufType = .Storage, .length = 100, .dataSize = @sizeOf(Object) } } };
pub const cameraUB = ResourceInf{ .id = 40, .memUse = .Gpu, .inf = .{ .bufInf = .{ .bufType = .Storage, .length = 1, .dataSize = @sizeOf(CameraData) } } };

pub const compImg = ResourceInf{ .id = 3, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 500, .height = 500, .depth = 1 } } } };
pub const grapImg = ResourceInf{ .id = 5, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 300, .height = 300, .depth = 1 } } } };
pub const meshImg = ResourceInf{ .id = 7, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 100, .height = 100, .depth = 1 } } } };
pub const taskImg = ResourceInf{ .id = 9, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } } } };
pub const testImg = ResourceInf{ .id = 10, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } } } };
pub const grapDepthImg = ResourceInf{ .id = 11, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Depth, .extent = .{ .width = 1920, .height = 1080, .depth = 1 }, .format = vk.VK_FORMAT_D32_SFLOAT } } };

pub const computeTest: Pass = .{
    .shaderIds = &.{sc.t1Comp.id},
    .shaderUsages = &.{
        .{ .id = objectSB.id, .stage = .Compute, .access = .ShaderRead },
        .{ .id = cameraUB.id, .stage = .Compute, .access = .ShaderRead },
        .{ .id = compImg.id, .stage = .Compute, .access = .ShaderWrite, .layout = .General },
    },
    .kind = .{
        .computeOnImage = .{
            .renderImgId = compImg.id,
            .workgroups = .{ .x = 8, .y = 8, .z = 1 },
        },
    },
};

const graphicsTest: Pass = .{
    .shaderIds = &.{ sc.t2Vert.id, sc.t2Frag.id },
    .shaderUsages = &.{
        .{ .id = objectSB.id, .stage = .FragShader, .access = .ShaderRead },
        .{ .id = cameraUB.id, .stage = .Compute, .access = .ShaderRead },
    },
    .kind = .{
        .graphics = .{
            .renderImgId = grapImg.id,
            .vertexCount = 3,
            .instanceCount = 1,
            .colorAtts = &.{
                .{ .id = grapImg.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .Attachment, .clear = false },
            },
            .depthAtt = .{ .id = grapDepthImg.id, .stage = .EarlyFragTest, .access = .DepthStencilRead, .layout = .Attachment, .clear = false },
        },
    },
};

const meshTest: Pass = .{
    .shaderIds = &.{ sc.t3Mesh.id, sc.t3Frag.id },
    .shaderUsages = &.{
        .{ .id = objectSB.id, .stage = .FragShader, .access = .ShaderRead },
        .{ .id = cameraUB.id, .stage = .Compute, .access = .ShaderRead },
    },
    .kind = .{
        .taskOrMesh = .{
            .renderImgId = meshImg.id,
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .colorAtts = &.{
                .{ .id = meshImg.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .Attachment, .clear = false },
            },
        },
    },
};

const taskTest: Pass = .{
    .shaderIds = &.{ sc.t4Task.id, sc.t4Mesh.id, sc.t4Frag.id },
    .shaderUsages = &.{
        .{ .id = objectSB.id, .stage = .FragShader, .access = .ShaderRead },
        .{ .id = cameraUB.id, .stage = .Compute, .access = .ShaderRead },
    },
    .kind = .{
        .taskOrMesh = .{
            .renderImgId = taskImg.id,
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .colorAtts = &.{
                .{ .id = taskImg.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .Attachment, .clear = false },
            },
        },
    },
};

const gridTest: Pass = .{
    .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id },
    .shaderUsages = &.{
        .{ .id = cameraUB.id, .stage = .Compute, .access = .ShaderRead },
    },
    .kind = .{
        .taskOrMesh = .{
            .renderImgId = taskImg.id,
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .colorAtts = &.{
                .{ .id = taskImg.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .Attachment, .clear = false },
            },
        },
    },
};

pub const renderSequence: []const Pass = &.{ computeTest, graphicsTest, meshTest, taskTest, gridTest };
