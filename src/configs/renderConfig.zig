const vk = @import("../modules/vk.zig").c;
const Object = @import("../ecs/EntityManager.zig").Object;
const CameraData = @import("../core/Camera.zig").CameraData;
const Buffer = @import("../vulkan/resources/Buffer.zig").Buffer;
const Texture = @import("../vulkan/resources/Texture.zig").Texture;
const ResourceState = @import("../vulkan/RenderGraph.zig").ResourceState;
const Pass = @import("../vulkan/Pass.zig").Pass;
const Attachment = @import("../vulkan/Pass.zig").Attachment;
const TextureUse = @import("../vulkan/Pass.zig").TextureUse;
const BufferUse = @import("../vulkan/Pass.zig").BufferUse;
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

pub const objectSB = Buffer.create(1, .Gpu, .Storage, 100, Object);
pub const cameraUB = Buffer.create(40, .Gpu, .Storage, 1, CameraData);

pub const compTex = Texture.create(3, .Gpu, .Color, 500, 500, 1, RENDER_IMG_FORMAT);
pub const grapTex = Texture.create(5, .Gpu, .Color, 300, 300, 1, RENDER_IMG_FORMAT);
pub const meshTex = Texture.create(7, .Gpu, .Color, 100, 100, 1, RENDER_IMG_FORMAT);
pub const taskTex = Texture.create(9, .Gpu, .Color, 1920, 1920, 1, RENDER_IMG_FORMAT);
pub const testTex = Texture.create(10, .Gpu, .Color, 1920, 1920, 1, RENDER_IMG_FORMAT);
pub const grapDepthTex = Texture.create(11, .Gpu, .Depth, 1920, 1920, 1, vk.VK_FORMAT_D32_SFLOAT);

pub const computeTest: Pass = .{
    .shaderIds = &.{sc.t1Comp.id},
    .passType = Pass.ComputeOnImage(.{
        .mainTexId = compTex.texId,
        .workgroups = .{ .x = 8, .y = 8, .z = 1 },
    }),
    .bufUses = &.{
        BufferUse.create(objectSB.bufId, .ComputeShader, .ShaderRead, 0),
        BufferUse.create(cameraUB.bufId, .ComputeShader, .ShaderRead, 1),
    },
    .texUses = &.{
        TextureUse.create(compTex.texId, .ComputeShader, .ShaderWrite, .General, 2),
    },
};

const graphicsTest: Pass = .{
    .shaderIds = &.{ sc.t2Frag.id, sc.t2Vert.id },
    .passType = Pass.Graphics(.{
        .mainTexId = grapTex.texId,
        .colorAtts = &.{Attachment.create(grapTex.texId, .ColorAtt, .ColorAttWrite, false)},
        .depthAtt = Attachment.create(grapDepthTex.texId, .EarlyFragTest, .DepthStencilRead, false),
    }),
    .bufUses = &.{
        BufferUse.create(objectSB.bufId, .FragShader, .ShaderRead, 0),
        BufferUse.create(cameraUB.bufId, .ComputeShader, .ShaderRead, 1),
    },
};

const meshTest: Pass = .{
    .shaderIds = &.{ sc.t3Mesh.id, sc.t3Frag.id },
    .passType = Pass.TaskOrMesh(.{
        .mainTexId = meshTex.texId,
        .workgroups = .{ .x = 1, .y = 1, .z = 1 },
        .colorAtts = &.{Attachment.create(meshTex.texId, .ColorAtt, .ColorAttWrite, false)},
    }),
    .bufUses = &.{
        BufferUse.create(objectSB.bufId, .FragShader, .ShaderRead, 0),
        BufferUse.create(cameraUB.bufId, .ComputeShader, .ShaderRead, 1),
    },
};

const taskTest: Pass = .{
    .shaderIds = &.{ sc.t4Task.id, sc.t4Mesh.id, sc.t4Frag.id },
    .passType = Pass.TaskOrMesh(.{
        .mainTexId = taskTex.texId,
        .workgroups = .{ .x = 1, .y = 1, .z = 1 },
        .colorAtts = &.{Attachment.create(taskTex.texId, .ColorAtt, .ColorAttWrite, false)},
    }),
    .bufUses = &.{
        BufferUse.create(objectSB.bufId, .FragShader, .ShaderRead, 0),
        BufferUse.create(cameraUB.bufId, .ComputeShader, .ShaderRead, 1),
    },
};

const gridTest: Pass = .{
    .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id },
    .passType = Pass.TaskOrMesh(.{
        .mainTexId = taskTex.texId,
        .workgroups = .{ .x = 1, .y = 1, .z = 1 },
        .colorAtts = &.{Attachment.create(taskTex.texId, .ColorAtt, .ColorAttWrite, false)},
    }),
    .bufUses = &.{
        BufferUse.create(cameraUB.bufId, .TaskShader, .ShaderRead, 0),
    },
};

pub const renderSequence: []const Pass = &.{ computeTest, graphicsTest, meshTest, taskTest, gridTest };
