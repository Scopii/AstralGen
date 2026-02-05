const Attachment = @import("../vulkan/types/base/Pass.zig").Attachment;
const TextureUse = @import("../vulkan/types/base/Pass.zig").TextureUse;
const BufferUse = @import("../vulkan/types/base/Pass.zig").BufferUse;
const Texture = @import("../vulkan/types/res/Texture.zig").Texture;
const Buffer = @import("../vulkan/types/res/Buffer.zig").Buffer;
const CameraData = @import("../core/Camera.zig").CameraData;
const Pass = @import("../vulkan/types/base/Pass.zig").Pass;
const Object = @import("../ecs/EntityManager.zig").Object;
const vhT = @import("../vulkan/help/Types.zig");
const vk = @import("../modules/vk.zig").c;
const sc = @import("shaderConfig.zig");

// Vulkan Validation Layers
pub const VALIDATION = true;
pub const GPU_VALIDATION = false;
pub const BEST_PRACTICES = false;

pub const SWAPCHAIN_PROFILING = false;
pub const CPU_PROFILING = false;
pub const GPU_PROFILING = false;
pub const GPU_QUERYS = 63;
pub const GPU_READBACK = false;

pub const EARLY_GPU_WAIT = true; // Lower Latency, more CPU Stutters (Reflex Mode)

// Rendering, Swapchains and Windows
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = vk.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const MAX_WINDOWS: u8 = 8;

pub const BUF_MAX = 63;
pub const STORAGE_TEX_MAX = 31;
pub const SAMPLED_TEX_MAX = 31;
pub const TEX_MAX = STORAGE_TEX_MAX + SAMPLED_TEX_MAX;
pub const RESOURCE_MAX = TEX_MAX + BUF_MAX;
pub const STAGING_BUF_SIZE = 32 * 1024 * 1024; // Bytes

pub const TEX_COLOR_FORMAT = vk.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const TEX_DEPTH_FORMAT = vk.VK_FORMAT_D32_SFLOAT;
pub const RENDER_TEX_AUTO_RESIZE = true;
pub const RENDER_TEX_STRETCH = true; // Ignored on AUTO_RESIZE

// Descriptors and Bindings
pub const STORAGE_TEX_BINDING = 0;
pub const STORAGE_BUF_BINDING = 1;
pub const SAMPLED_TEX_BINDING = 2;

pub const bindingRegistry: []const struct { binding: u32, descType: vk.VkDescriptorType, len: u32 } = &.{
    .{ .binding = STORAGE_TEX_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .len = STORAGE_TEX_MAX },
    .{ .binding = STORAGE_BUF_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .len = BUF_MAX },
    .{ .binding = SAMPLED_TEX_BINDING, .descType = vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, .len = SAMPLED_TEX_MAX },
};

// Buffers
pub const indirectSB = Buffer.create(.{ .id = .{ .val = 41 }, .mem = .Gpu, .typ = .Indirect, .len = 1, .elementSize = @sizeOf(vhT.IndirectData), .update = .PerFrame });
pub const readbackSB = Buffer.create(.{ .id = .{ .val = 45 }, .mem = .Gpu, .typ = .Storage, .len = 1, .elementSize = @sizeOf(vhT.ReadbackData), .update = .Overwrite });

pub const objectSB = Buffer.create(.{ .id = .{ .val = 1 }, .mem = .Gpu, .typ = .Storage, .len = 100, .elementSize = @sizeOf(Object), .update = .PerFrame });
pub const cameraUB = Buffer.create(.{ .id = .{ .val = 40 }, .mem = .Gpu, .typ = .Uniform, .len = 1, .elementSize = @sizeOf(CameraData), .update = .PerFrame });
pub const BUFFERS: []const Buffer.BufInf = &.{ objectSB, cameraUB, indirectSB, readbackSB };

// Textures
pub const quantTex = Texture.create(.{ .id = .{ .val = 5 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1080, .update = .PerFrame });
pub const quantDepthTex = Texture.create(.{ .id = .{ .val = 11 }, .mem = .Gpu, .typ = .Depth, .width = 1920, .height = 1080, .update = .PerFrame });
pub const TEXTURES: []const Texture.TexInf = &.{ quantTex, quantDepthTex };

// Passes
pub const PASSES: []const Pass = &.{ quantComp, quant };

pub const quantComp: Pass = .{
    .name = "Quant-Comp",
    .shaderIds = &.{sc.quantComp.id},
    .typ = Pass.createCompute(.{
        .workgroups = .{ .x = 1, .y = 1, .z = 1 },
    }),
    .bufUses = &.{
        BufferUse.init(indirectSB.id, .ComputeShader, .ShaderReadWrite, 0),
        BufferUse.init(objectSB.id, .ComputeShader, .ShaderRead, 1),
    },
};

const quant: Pass = .{
    .name = "Quant",
    .shaderIds = &.{ sc.quantMesh.id, sc.quantFrag.id },
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.ClassicTyp.taskMeshData(.{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = .{ .id = indirectSB.id, .offset = 0 },
        }),
        .mainTexId = quantTex.id,
        .colorAtts = &.{Attachment.init(quantTex.id, .ColorAtt, .ColorAttReadWrite, true)},
        .depthAtt = Attachment.init(quantDepthTex.id, .EarlyFragTest, .DepthStencilWrite, true),
        .state = .{
            // .polygonMode = vk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
            // .lineWidth = 2.0,
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_LESS,
            .cullMode = vk.VK_CULL_MODE_NONE,
            // .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        },
    }),
    .bufUses = &.{
        BufferUse.init(indirectSB.id, .DrawIndirect, .IndirectRead, null),
        BufferUse.init(cameraUB.id, .FragShader, .ShaderRead, 1),
    },
};

// pub const compTex = Texture.create(.{ .id = .{ .val = 1 }, .mem = .Gpu, .typ = .Color, .width = 500, .height = 500 });
// pub const grapTex = Texture.create(.{ .id = .{ .val = 2 }, .mem = .Gpu, .typ = .Color, .width = 300, .height = 300 });
// pub const meshTex = Texture.create(.{ .id = .{ .val = 3 }, .mem = .Gpu, .typ = .Color, .width = 100, .height = 100 });
// pub const taskTex = Texture.create(.{ .id = .{ .val = 4 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1920 });
// pub const testTex = Texture.create(.{ .id = .{ .val = 5 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1920 });
// pub const depthTex = Texture.create(.{ .id = .{ .val = 11 }, .mem = .Gpu, .typ = .Depth, .width = 1920, .height = 1920 });
// pub const textures: []const Texture.TexInf = &.{ compTex, grapTex, meshTex, taskTex, testTex, depthTex };

// pub const passes: []const Pass = &.{ compTest, taskTest, gridTest, grapTest, meshTest, indirectCompTest, indirectTaskTest };

// pub const compTest: Pass = .{
//     .name = "CompTest",
//     .shaderIds = &.{sc.t1Comp.id},
//     .typ = Pass.createCompute(.{
//         .mainTexId = compTex.id,
//         .workgroups = .{ .x = 8, .y = 8, .z = 1 },
//     }),
//     .bufUses = &.{
//         BufferUse.init(objectSB.id, .ComputeShader, .ShaderRead, 0),
//         BufferUse.init(cameraUB.id, .ComputeShader, .ShaderRead, 1),
//         BufferUse.init(readbackSB.id, .ComputeShader, .ShaderWrite, 3),
//     },
//     .texUses = &.{
//         TextureUse.init(compTex.id, .ComputeShader, .ShaderWrite, .General, 2),
//     },
// };

// const grapTest: Pass = .{
//     .name = "GrapTest",
//     .shaderIds = &.{ sc.t2Frag.id, sc.t2Vert.id },
//     .typ = Pass.createClassic(.{
//         .classicTyp = Pass.ClassicTyp.graphicsData(.{}),
//         .mainTexId = grapTex.id,
//         .colorAtts = &.{Attachment.init(grapTex.id, .ColorAtt, .ColorAttReadWrite, false)},
//         .depthAtt = Attachment.init(depthTex.id, .EarlyFragTest, .DepthStencilRead, false),
//     }),
//     .bufUses = &.{
//         BufferUse.init(objectSB.id, .FragShader, .ShaderRead, 0),
//         BufferUse.init(cameraUB.id, .FragShader, .ShaderRead, 1),
//     },
// };

// const meshTest: Pass = .{
//     .name = "MeshTest",
//     .shaderIds = &.{ sc.t3Mesh.id, sc.t3Frag.id },
//     .typ = Pass.createClassic(.{
//         .classicTyp = Pass.ClassicTyp.taskMeshData(.{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } }),
//         .mainTexId = meshTex.id,
//         .colorAtts = &.{Attachment.init(meshTex.id, .ColorAtt, .ColorAttReadWrite, false)},
//     }),
//     .bufUses = &.{
//         BufferUse.init(objectSB.id, .FragShader, .ShaderRead, 0),
//         BufferUse.init(cameraUB.id, .FragShader, .ShaderRead, 1),
//     },
// };

// const taskTest: Pass = .{
//     .name = "TaskTest",
//     .shaderIds = &.{ sc.t4Task.id, sc.t4Mesh.id, sc.t4Frag.id },
//     .typ = Pass.createClassic(.{
//         .classicTyp = Pass.ClassicTyp.taskMeshData(.{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } }),
//         .mainTexId = taskTex.id,
//         .colorAtts = &.{Attachment.init(taskTex.id, .ColorAtt, .ColorAttReadWrite, false)},
//     }),
//     .bufUses = &.{
//         BufferUse.init(objectSB.id, .FragShader, .ShaderRead, 0),
//         BufferUse.init(cameraUB.id, .FragShader, .ShaderRead, 1),
//     },
// };

// const gridTest: Pass = .{
//     .name = "GridTest",
//     .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id },
//     .typ = Pass.createClassic(.{
//         .classicTyp = Pass.ClassicTyp.taskMeshData(.{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } }),
//         .mainTexId = taskTex.id,
//         .colorAtts = &.{Attachment.init(taskTex.id, .ColorAtt, .ColorAttReadWrite, true)},
//     }),
//     .bufUses = &.{
//         BufferUse.init(cameraUB.id, .TaskShader, .ShaderRead, 0),
//     },
// };

// pub const indirectCompTest: Pass = .{
//     .name = "IndirectCompTest",
//     .shaderIds = &.{sc.indirectComp.id},
//     .typ = Pass.createCompute(.{
//         .workgroups = .{ .x = 1, .y = 1, .z = 1 },
//     }),
//     .bufUses = &.{
//         BufferUse.init(indirectSB.id, .ComputeShader, .ShaderReadWrite, 0),
//     },
// };

// const indirectTaskTest: Pass = .{
//     .name = "IndirectTaskTest",
//     .shaderIds = &.{ sc.indirectTask.id, sc.indirectMesh.id, sc.indirectFrag.id },
//     .typ = Pass.createClassic(.{
//         .classicTyp = Pass.ClassicTyp.taskMeshData(.{
//             .workgroups = .{ .x = 1, .y = 1, .z = 1 },
//             .indirectBuf = .{ .id = indirectSB.id, .offset = 0 },
//         }),
//         .mainTexId = taskTex.id,
//         .colorAtts = &.{Attachment.init(taskTex.id, .ColorAtt, .ColorAttReadWrite, false)},
//     }),
//     .bufUses = &.{
//         BufferUse.init(indirectSB.id, .DrawIndirect, .IndirectRead, null),
//     },
// };
