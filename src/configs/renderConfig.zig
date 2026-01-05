const vk = @import("../modules/vk.zig").c;
const Object = @import("../ecs/EntityManager.zig").Object;
const CameraData = @import("../core/Camera.zig").CameraData;
const ResourceInf = @import("../vulkan/resources/Resource.zig").ResourceInf;
const ResourceState = @import("../vulkan/RenderGraph.zig").ResourceState;
const Pass = @import("../vulkan/Pass.zig").Pass;
const Attachment = @import("../vulkan/Pass.zig").Attachment;
const ResourceUse = @import("../vulkan/Pass.zig").ResourceUse;
const sc = @import("shaderConfig.zig");
const ve = @import("../vulkan/Helpers.zig");

// Rendering, Swapchains and Windows
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = vk.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const MAX_WINDOWS: u8 = 8;

pub const GPU_BUF_MAX = 64;
pub const GPU_IMG_MAX = 32;
pub const GPU_RESOURCE_MAX = GPU_BUF_MAX + GPU_IMG_MAX;

pub const RENDER_IMG_FORMAT = vk.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const RENDER_IMG_AUTO_RESIZE = true;
pub const RENDER_IMG_STRETCH = true; // Ignored on AUTO_RESIZE

pub const STORAGE_IMG_BINDING = 0;
pub const STORAGE_BUF_BINDING = 1;
pub const SAMPLED_IMG_BINDING = 2;

pub const bindingRegistry: []const struct { binding: u32, descType: vk.VkDescriptorType, arrayLength: u32 } = &.{
    .{ .binding = STORAGE_IMG_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .arrayLength = GPU_IMG_MAX },
    .{ .binding = STORAGE_BUF_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .arrayLength = GPU_BUF_MAX },
    .{ .binding = SAMPLED_IMG_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, .arrayLength = GPU_IMG_MAX },
};

pub const objectSB = ResourceInf.Buffer(1, .Gpu, .Storage, 100, Object);
pub const cameraUB = ResourceInf.Buffer(40, .Gpu, .Storage, 1, CameraData);

pub const compImg = ResourceInf.Image(3, .Gpu, .Color, 500, 500, 1, RENDER_IMG_FORMAT);
pub const grapImg = ResourceInf.Image(5, .Gpu, .Color, 300, 300, 1, RENDER_IMG_FORMAT);
pub const meshImg = ResourceInf.Image(7, .Gpu, .Color, 100, 100, 1, RENDER_IMG_FORMAT);
pub const taskImg = ResourceInf.Image(9, .Gpu, .Color, 1920, 1920, 1, RENDER_IMG_FORMAT);
pub const testImg = ResourceInf.Image(10, .Gpu, .Color, 1920, 1920, 1, RENDER_IMG_FORMAT);
pub const grapDepthImg = ResourceInf.Image(11, .Gpu, .Depth, 1920, 1920, 1, vk.VK_FORMAT_D32_SFLOAT);

pub const computeTest: Pass = .{
    .shaderIds = &.{sc.t1Comp.id},
    .passType = Pass.ComputeOnImage(.{
        .mainImgId = compImg.id,
        .workgroups = .{ .x = 8, .y = 8, .z = 1 },
    }),
    .shaderBuffers = &.{
        ResourceUse.create(objectSB.id, .ComputeShader, .ShaderRead, .General),
        ResourceUse.create(cameraUB.id, .ComputeShader, .ShaderRead, .General),
    },
    .shaderImages = &.{
        ResourceUse.create(compImg.id, .ComputeShader, .ShaderWrite, .General),
    },
};

const graphicsTest: Pass = .{
    .shaderIds = &.{ sc.t2Frag.id, sc.t2Vert.id },
    .passType = Pass.Graphics(.{
        .mainImgId = grapImg.id,
        .colorAtts = &.{Attachment.create(grapImg.id, .ColorAtt, .ColorAttWrite, false)},
        .depthAtt = Attachment.create(grapDepthImg.id, .EarlyFragTest, .DepthStencilRead, false),
    }),
    .shaderBuffers = &.{
        ResourceUse.create(objectSB.id, .FragShader, .ShaderRead, .General),
        ResourceUse.create(cameraUB.id, .ComputeShader, .ShaderRead, .General),
    },
};

const meshTest: Pass = .{
    .shaderIds = &.{ sc.t3Mesh.id, sc.t3Frag.id },
    .passType = Pass.TaskOrMesh(.{
        .mainImgId = meshImg.id,
        .workgroups = .{ .x = 1, .y = 1, .z = 1 },
        .colorAtts = &.{Attachment.create(meshImg.id, .ColorAtt, .ColorAttWrite, false)},
    }),
    .shaderBuffers = &.{
        ResourceUse.create(objectSB.id, .FragShader, .ShaderRead, .General),
        ResourceUse.create(cameraUB.id, .ComputeShader, .ShaderRead, .General),
    },
};

const taskTest: Pass = .{
    .shaderIds = &.{ sc.t4Task.id, sc.t4Mesh.id, sc.t4Frag.id },
    .passType = Pass.TaskOrMesh(.{
        .mainImgId = taskImg.id,
        .workgroups = .{ .x = 1, .y = 1, .z = 1 },
        .colorAtts = &.{Attachment.create(taskImg.id, .ColorAtt, .ColorAttWrite, false)},
    }),
    .shaderBuffers = &.{
        ResourceUse.create(objectSB.id, .FragShader, .ShaderRead, .General),
        ResourceUse.create(cameraUB.id, .ComputeShader, .ShaderRead, .General),
    },
};

const gridTest: Pass = .{
    .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id },
    .passType = Pass.TaskOrMesh(.{
        .mainImgId = taskImg.id,
        .workgroups = .{ .x = 1, .y = 1, .z = 1 },
        .colorAtts = &.{Attachment.create(taskImg.id, .ColorAtt, .ColorAttWrite, false)},
    }),
    .shaderBuffers = &.{
        ResourceUse.create(cameraUB.id, .TaskShader, .ShaderRead, .General),
    },
};

pub const renderSequence: []const Pass = &.{ computeTest, graphicsTest, meshTest, taskTest, gridTest };
