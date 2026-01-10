const Attachment = @import("../vulkan/components/Pass.zig").Attachment;
const TextureUse = @import("../vulkan/components/Pass.zig").TextureUse;
const BufferUse = @import("../vulkan/components/Pass.zig").BufferUse;
const Texture = @import("../vulkan/components/Texture.zig").Texture;
const Buffer = @import("../vulkan/components/Buffer.zig").Buffer;
const CameraData = @import("../core/Camera.zig").CameraData;
const Pass = @import("../vulkan/components/Pass.zig").Pass;
const Object = @import("../ecs/EntityManager.zig").Object;
const ve = @import("../vulkan/systems/Helpers.zig");
const vk = @import("../modules/vk.zig").c;
const sc = @import("shaderConfig.zig");

// Rendering, Swapchains and Windows
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = vk.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const MAX_WINDOWS: u8 = 8;

pub const BUF_MAX = 64;
pub const TEX_MAX = 32;
pub const GPU_RESOURCE_MAX = BUF_MAX + TEX_MAX;
pub const STAGING_BUF_SIZE = 32 * 1024 * 1024;

pub const TEX_COLOR_FORMAT = vk.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const TEX_DEPTH_FORMAT = vk.VK_FORMAT_D32_SFLOAT;
pub const RENDER_TEX_AUTO_RESIZE = true;
pub const RENDER_TEX_STRETCH = true; // Ignored on AUTO_RESIZE

pub const STORAGE_TEX_BINDING = 0;
pub const STORAGE_BUF_BINDING = 1;
pub const SAMPLED_TEX_BINDING = 2;

pub const bindingRegistry: []const struct { binding: u32, descType: vk.VkDescriptorType, len: u32 } = &.{
    .{ .binding = STORAGE_TEX_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .len = TEX_MAX },
    .{ .binding = STORAGE_BUF_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .len = BUF_MAX },
    .{ .binding = SAMPLED_TEX_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, .len = TEX_MAX },
};

pub const objectSB = Buffer.create(.{ .id = .{ .val = 1 }, .mem = .Gpu, .typ = .Storage, .len = 100, .elementSize = @sizeOf(Object) });
pub const cameraUB = Buffer.create(.{ .id = .{ .val = 40 }, .mem = .Gpu, .typ = .Storage, .len = 1, .elementSize = @sizeOf(CameraData) });
pub const indirectSB = Buffer.create(.{ .id = .{ .val = 41 }, .mem = .Gpu, .typ = .Indirect, .len = 1, .elementSize = @sizeOf(struct { x: u32, y: u32, z: u32, count: u32 }) });
pub const buffers: []const Buffer.BufInf = &.{ objectSB, cameraUB, indirectSB };

pub const compTex = Texture.create(.{ .id = .{ .val = 1 }, .mem = .Gpu, .typ = .Color, .width = 500, .height = 500 });
pub const grapTex = Texture.create(.{ .id = .{ .val = 2 }, .mem = .Gpu, .typ = .Color, .width = 300, .height = 300 });
pub const meshTex = Texture.create(.{ .id = .{ .val = 3 }, .mem = .Gpu, .typ = .Color, .width = 100, .height = 100 });
pub const taskTex = Texture.create(.{ .id = .{ .val = 4 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1920 });
pub const testTex = Texture.create(.{ .id = .{ .val = 5 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1920 });
pub const depthTex = Texture.create(.{ .id = .{ .val = 11 }, .mem = .Gpu, .typ = .Depth, .width = 1920, .height = 1920 });
pub const textures: []const Texture.TexInf = &.{ compTex, grapTex, meshTex, taskTex, testTex, depthTex };

pub const compTest: Pass = .{
    .shaderIds = &.{sc.t1Comp.id},
    .typ = Pass.createCompute(.{
        .mainTexId = compTex.id,
        .workgroups = .{ .x = 8, .y = 8, .z = 1 },
    }),
    .bufUses = &.{
        BufferUse.init(objectSB.id, .ComputeShader, .ShaderRead, 0),
        BufferUse.init(cameraUB.id, .ComputeShader, .ShaderRead, 1),
    },
    .texUses = &.{
        TextureUse.init(compTex.id, .ComputeShader, .ShaderWrite, .General, 2),
    },
};

const grapTest: Pass = .{
    .shaderIds = &.{ sc.t2Frag.id, sc.t2Vert.id },
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.graphicsData(.{}),
        .mainTexId = grapTex.id,
        .colorAtts = &.{Attachment.init(grapTex.id, .ColorAtt, .ColorAttWrite, false)},
        .depthAtt = Attachment.init(depthTex.id, .EarlyFragTest, .DepthStencilRead, false),
    }),
    .bufUses = &.{
        BufferUse.init(objectSB.id, .FragShader, .ShaderRead, 0),
        BufferUse.init(cameraUB.id, .ComputeShader, .ShaderRead, 1),
    },
};

const meshTest: Pass = .{
    .shaderIds = &.{ sc.t3Mesh.id, sc.t3Frag.id },
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.taskMeshData(.{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } }),
        .mainTexId = meshTex.id,
        .colorAtts = &.{Attachment.init(meshTex.id, .ColorAtt, .ColorAttWrite, false)},
    }),
    .bufUses = &.{
        BufferUse.init(objectSB.id, .FragShader, .ShaderRead, 0),
        BufferUse.init(cameraUB.id, .ComputeShader, .ShaderRead, 1),
    },
};

const taskTest: Pass = .{
    .shaderIds = &.{ sc.t4Task.id, sc.t4Mesh.id, sc.t4Frag.id },
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.taskMeshData(.{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } }),
        .mainTexId = taskTex.id,
        .colorAtts = &.{Attachment.init(taskTex.id, .ColorAtt, .ColorAttWrite, false)},
    }),
    .bufUses = &.{
        BufferUse.init(objectSB.id, .FragShader, .ShaderRead, 0),
        BufferUse.init(cameraUB.id, .ComputeShader, .ShaderRead, 1),
    },
};

const gridTest: Pass = .{
    .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id },
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.taskMeshData(.{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } }),
        .mainTexId = taskTex.id,
        .colorAtts = &.{Attachment.init(taskTex.id, .ColorAtt, .ColorAttWrite, false)},
    }),
    .bufUses = &.{
        BufferUse.init(cameraUB.id, .TaskShader, .ShaderRead, 0),
    },
};

pub const indirectCompTest: Pass = .{
    .shaderIds = &.{sc.indirectComp.id},
    .typ = Pass.createCompute(.{
        .workgroups = .{ .x = 1, .y = 1, .z = 1 },
    }),
    .bufUses = &.{
        BufferUse.init(indirectSB.id, .ComputeShader, .ShaderReadWrite, 0),
    },
};

const indirectMeshTest: Pass = .{
    .shaderIds = &.{ sc.indirectTask.id, sc.indirectMesh.id, sc.indirectFrag.id },
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.taskMeshIndirectData(.{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = .{ .id = indirectSB.id, .offset = 0 },
        }),
        .mainTexId = taskTex.id,
        .colorAtts = &.{Attachment.init(taskTex.id, .ColorAtt, .ColorAttWrite, false)},
    }),
    .bufUses = &.{
        BufferUse.init(indirectSB.id, .DrawIndirect, .IndirectRead, null),
    },
};

pub const passes: []const Pass = &.{ compTest, grapTest, meshTest, taskTest, gridTest, indirectCompTest, indirectMeshTest };
