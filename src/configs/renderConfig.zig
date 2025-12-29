const vk = @import("../modules/vk.zig").c;
const Object = @import("../ecs/EntityManager.zig").Object;
const sc = @import("shaderConfig.zig");
const PipeAccess = @import("../vulkan/RenderGraph.zig").PipeAccess;
const PipeStage = @import("../vulkan/RenderGraph.zig").PipeStage;
const ImageLayout = @import("../vulkan/RenderGraph.zig").ImageLayout;

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
    resUsages: []const ResourceUsage,
    renderImgId: ?u32 = null,

    kind: union(enum) {
        compute: struct {
            workgroups: Dispatch,
        },
        taskOrMesh: struct {
            colorAtts: []const Attachment,
            depthAtt: ?Attachment = null,
            stencilAtt: ?Attachment = null,
            workgroups: Dispatch,
        },
        graphics: struct {
            colorAtts: []const Attachment,
            depthAtt: ?Attachment = null,
            stencilAtt: ?Attachment = null,
            vertexCount: u32 = 3,
            instanceCount: u32 = 1,
        },
    },
    pub const Dispatch = struct { x: u32, y: u32, z: u32 };
    pub const Attachment = struct { resUsage: ResourceUsage, clear: bool };
    pub const ResourceUsage = struct { id: u32, stage: PipeStage = .TopOfPipe, access: PipeAccess = .None, layout: ImageLayout = .General };
};

pub const ImgType = enum { Color, Depth, Stencil };

pub const ResourceInf = struct {
    id: u32,
    memUse: MemUsage,
    inf: union(enum) { imgInf: ImgInf, bufInf: BufInf },

    pub const ImgInf = struct { extent: vk.VkExtent3D, format: c_uint = RENDER_IMG_FORMAT, imgType: ImgType };
    pub const BufInf = struct { dataSize: u64 = 0, length: u32, usage: enum { Storage, Uniform, Index, Vertex, Staging } };
    pub const MemUsage = enum { Gpu, CpuWrite, CpuRead };
};

pub const STORAGE_IMG_BINDING = 0;
pub const STORAGE_BUF_BINDING = 1;

pub const bindingRegistry: []const struct { binding: u32, descType: vk.VkDescriptorType, arrayLength: u32 } = &.{
    .{ .binding = STORAGE_IMG_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .arrayLength = GPU_IMG_MAX },
    .{ .binding = STORAGE_BUF_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .arrayLength = GPU_BUF_MAX },
};

pub const buf1 = ResourceInf{ .id = 1, .memUse = .CpuWrite, .inf = .{ .bufInf = .{ .usage = .Storage, .length = 100, .dataSize = @sizeOf(Object) } } };
pub const img1 = ResourceInf{ .id = 3, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 500, .height = 500, .depth = 1 } } } };
pub const img2 = ResourceInf{ .id = 5, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 300, .height = 300, .depth = 1 } } } };
pub const img3 = ResourceInf{ .id = 7, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 100, .height = 100, .depth = 1 } } } };
pub const img4 = ResourceInf{ .id = 9, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } } } };
pub const img5 = ResourceInf{ .id = 10, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } } } };
pub const img6 = ResourceInf{ .id = 11, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Depth, .extent = .{ .width = 1920, .height = 1080, .depth = 1 }, .format = vk.VK_FORMAT_D32_SFLOAT } } };

pub const computeTest: Pass = .{
    .shaderIds = &.{sc.t1Comp.id},
    .renderImgId = img1.id,
    .kind = .{
        .compute = .{ .workgroups = .{ .x = 8, .y = 8, .z = 1 } },
    },
    .resUsages = &.{
        .{ .id = img1.id, .stage = .Compute, .access = .ShaderWrite, .layout = .General },
    },
};

const graphicsTest: Pass = .{
    .shaderIds = &.{ sc.t2Vert.id, sc.t2Frag.id },
    .renderImgId = img2.id,
    .kind = .{
        .graphics = .{
            .colorAtts = &.{
                .{ .resUsage = .{ .id = img2.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .ColorAtt }, .clear = false },
            },
            .depthAtt = .{ .resUsage = .{ .id = img6.id, .stage = .EarlyFragTest, .access = .DepthStencilRead, .layout = .DepthAtt }, .clear = false },
        },
    },
    .resUsages = &.{
    },
};

const meshTest: Pass = .{
    .shaderIds = &.{ sc.t3Mesh.id, sc.t3Frag.id },
    .renderImgId = img3.id,
    .kind = .{
        .taskOrMesh = .{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .colorAtts = &.{
                .{ .resUsage = .{ .id = img3.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .ColorAtt }, .clear = false },
            },
        },
    },
    .resUsages = &.{

    },
};

const taskTest: Pass = .{
    .shaderIds = &.{ sc.t4Task.id, sc.t4Mesh.id, sc.t4Frag.id },
    .renderImgId = img4.id,
    .kind = .{
        .taskOrMesh = .{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .colorAtts = &.{
                .{ .resUsage = .{ .id = img4.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .ColorAtt }, .clear = false },
            },
        },
    },
    .resUsages = &.{

    },
};

const gridTest: Pass = .{
    .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id },
    .renderImgId = img4.id,
    .kind = .{
        .taskOrMesh = .{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .colorAtts = &.{
                .{ .resUsage = .{ .id = img4.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .ColorAtt }, .clear = false },
            },
        },
    },
    .resUsages = &.{

    },
};

pub const renderSequence: []const Pass = &.{ computeTest, graphicsTest, meshTest, taskTest, gridTest };
