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
pub const MAX_WINDOWS: u8 = 16;

pub const GPU_BUF_MAX = 1024;
pub const GPU_IMG_MAX = 1024;
pub const GPU_RESOURCE_MAX = GPU_BUF_MAX + GPU_IMG_MAX;

pub const RENDER_IMG_BINDING = 0; // FOR UPDATING THE RENDER IMAGE ON WINDOW RESIZES
pub const RENDER_IMG_FORMAT = vk.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const RENDER_IMG_AUTO_RESIZE = true;
pub const RENDER_IMG_STRETCH = true; // Ignored on AUTO_RESIZE

pub const Pass = struct {
    shaderIds: []const u8,
    passType: PassType = .empty,
    attachments: []const Attachment,
    resUsages: []const ResourceUsage,
    clearColor: bool = false,
    clearDepth: bool = false,
    clearStencil: bool = false,

    pub const PassType = enum { computePass, graphicsPass, meshPass, taskMeshPass, vertexPass, empty };
    pub const Attachment = struct { id: u32, renderType: ImgType };
    pub const ResourceUsage = struct { id: u32, stage: PipeStage = .TopOfPipe, access: PipeAccess = .None, layout: ImageLayout = .General };
};

pub const ImgType = enum { Color, Depth, Stencil };

pub const ResourceInf = struct {
    id: u32,
    binding: u8,
    memUse: MemUsage,
    inf: union(enum) { imgInf: ImgInf, bufInf: BufInf },

    pub const ImgInf = struct { extent: vk.VkExtent3D, format: c_uint = RENDER_IMG_FORMAT, imgType: ImgType };
    pub const BufInf = struct { dataSize: u64 = 0, length: u32, usage: enum { Storage, Uniform, Index, Vertex, Staging } };
    pub const MemUsage = enum { Gpu, CpuWrite, CpuRead };
};

pub const DescriptorBinding = struct { binding: u32, descType: vk.VkDescriptorType, arrayLength: u32 };
pub const bindingRegistry: []const DescriptorBinding = &.{
    .{ .binding = 0, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .arrayLength = GPU_IMG_MAX },
    .{ .binding = 1, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .arrayLength = GPU_BUF_MAX },
};

pub const img1 = ResourceInf{ .id = 50, .binding = 0, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 500, .height = 500, .depth = 1 } } } };
pub const img2 = ResourceInf{ .id = 51, .binding = 0, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 300, .height = 300, .depth = 1 } } } };
pub const img3 = ResourceInf{ .id = 52, .binding = 0, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 100, .height = 100, .depth = 1 } } } };
pub const img4 = ResourceInf{ .id = 53, .binding = 0, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } } } };
pub const img5 = ResourceInf{ .id = 54, .binding = 0, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Color, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } } } };
pub const img6 = ResourceInf{ .id = 56, .binding = 0, .memUse = .Gpu, .inf = .{ .imgInf = .{ .imgType = .Depth, .extent = .{ .width = 1920, .height = 1080, .depth = 1 }, .format = vk.VK_FORMAT_D32_SFLOAT } } };
pub const buff1 = ResourceInf{ .id = 1, .binding = 1, .memUse = .CpuWrite, .inf = .{ .bufInf = .{ .usage = .Storage, .length = 100, .dataSize = @sizeOf(Object) } } };

pub const computeTest: Pass = .{
    .shaderIds = &.{sc.t1Comp.id},
    .attachments = &.{
        .{ .id = img1.id, .renderType = .Color },
    },
    .resUsages = &.{
        .{ .id = img1.id, .stage = .Compute, .access = .ShaderWrite, .layout = .General },
    },
};

pub const graphicsTest: Pass = .{
    .shaderIds = &.{ sc.t2Vert.id, sc.t2Frag.id },
    .attachments = &.{
        .{ .id = img2.id, .renderType = .Color },
        .{ .id = img6.id, .renderType = .Depth },
    },
    .resUsages = &.{
        .{ .id = img2.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .ColorAtt },
        .{ .id = img6.id, .stage = .EarlyFragTest, .access = .DepthStencilRead, .layout = .DepthAtt },
    },
};

pub const meshTest: Pass = .{
    .shaderIds = &.{ sc.t3Mesh.id, sc.t3Frag.id },
    .attachments = &.{
        .{ .id = img3.id, .renderType = .Color },
    },
    .resUsages = &.{
        .{ .id = img3.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .ColorAtt },
    },
};

pub const taskTest: Pass = .{
    .shaderIds = &.{ sc.t4Task.id, sc.t4Mesh.id, sc.t4Frag.id },
    .attachments = &.{
        .{ .id = img4.id, .renderType = .Color },
    },
    .resUsages = &.{
        .{ .id = img4.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .ColorAtt },
    },
};

pub const gridTest: Pass = .{
    .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id },
    .attachments = &.{
        .{ .id = img4.id, .renderType = .Color },
    },
    .resUsages = &.{
        .{ .id = img4.id, .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .ColorAtt },
    },
    .clearColor = false,
};

pub const renderSequence: []const Pass = &.{ computeTest, graphicsTest, meshTest, taskTest, gridTest };
