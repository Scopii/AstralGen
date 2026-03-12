const Attachment = @import("../vulkan/types/base/Pass.zig").Attachment;
const TextureUse = @import("../vulkan/types/base/Pass.zig").TextureUse;
const BufferUse = @import("../vulkan/types/base/Pass.zig").BufferUse;
const TextureMeta = @import("../vulkan/types/res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../vulkan/types/res/BufferMeta.zig").BufferMeta;
const CameraData = @import("../camera/Camera.zig").CameraData;
const Pass = @import("../vulkan/types/base/Pass.zig").Pass;
const Entity = @import("../entity/Entity.zig").Entity;
const vhT = @import("../vulkan/help/Types.zig");
const vk = @import("../.modules/vk.zig").c;
const sc = @import("shaderConfig.zig");

// Vulkan Validation Layers
pub const VALIDATION = true;
pub const GPU_VALIDATION = false;
pub const BEST_PRACTICES = false;
pub const ROBUST_VALIDATION = false;

// Normal Profiling
pub const GPU_PROFILING = false;
pub const GPU_QUERYS = 63;
pub const GPU_READBACK = false;
pub const CPU_PROFILING = false;
pub const SWAPCHAIN_PROFILING = false;

// Additional Debug Prints
pub const BARRIER_DEBUG = false;
pub const RESOURCE_DEBUG = true;
pub const DESCRIPTOR_DEBUG = true;

// Rendering, Swapchains and Windows
pub const EARLY_GPU_WAIT = true; // (Reflex Mode)
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = vk.VK_PRESENT_MODE_MAILBOX_KHR; //vk.VK_PRESENT_MODE_IMMEDIATE_KHR
pub const MAX_WINDOWS: u8 = 8;
pub const LINKED_TEX_MAX = 3;
pub const RENDER_TEX_AUTO_RESIZE = true;
pub const RENDER_TEX_STRETCH = true; // Ignored on AUTO_RESIZE

// Resource Information
pub const BUF_MAX = 63;
pub const STORAGE_TEX_MAX = 31;
pub const SAMPLED_TEX_MAX = 31;
pub const TEX_MAX = STORAGE_TEX_MAX + SAMPLED_TEX_MAX;
pub const RESOURCE_MAX = TEX_MAX + BUF_MAX;
pub const STAGING_BUF_SIZE = 32 * 1024 * 1024; // Bytes

pub const TEX_COLOR_FORMAT = vk.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const TEX_DEPTH_FORMAT = vk.VK_FORMAT_D32_SFLOAT;

// Buffers
pub const indirectSB = BufferMeta.create(.{ .id = .{ .val = 1 }, .mem = .Gpu, .typ = .Indirect, .len = 1, .elementSize = @sizeOf(vhT.IndirectData), .update = .PerFrame });
pub const readbackSB = BufferMeta.create(.{ .id = .{ .val = 2 }, .mem = .CpuRead, .typ = .Storage, .len = 1, .elementSize = @sizeOf(vhT.ReadbackData), .update = .PerFrame });

pub const objectSB = BufferMeta.create(.{ .id = .{ .val = 3 }, .mem = .Gpu, .typ = .Storage, .len = 20, .elementSize = @sizeOf(Entity), .update = .Rarely, .resize = .Fit });
pub const cameraUB = BufferMeta.create(.{ .id = .{ .val = 4 }, .mem = .Gpu, .typ = .Uniform, .len = 1, .elementSize = @sizeOf(CameraData), .update = .Often, .resize = .Fit });
pub const camera2UB = BufferMeta.create(.{ .id = .{ .val = 5 }, .mem = .Gpu, .typ = .Uniform, .len = 1, .elementSize = @sizeOf(CameraData), .update = .Often, .resize = .Fit });
pub const BUFFERS: []const BufferMeta.BufInf = &.{ objectSB, cameraUB, camera2UB, indirectSB, readbackSB };

// Textures
pub const quantTex = TextureMeta.create(.{ .id = .{ .val = 1 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1080, .update = .Rarely });
pub const quantDepthTex = TextureMeta.create(.{ .id = .{ .val = 2 }, .mem = .Gpu, .typ = .Depth, .width = 1920, .height = 1080, .update = .Rarely });

pub const quantDebugTex = TextureMeta.create(.{ .id = .{ .val = 3 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1080, .update = .Rarely });
pub const quantDebugDepthTex = TextureMeta.create(.{ .id = .{ .val = 4 }, .mem = .Gpu, .typ = .Depth, .width = 1920, .height = 1080, .update = .Rarely });
pub const TEXTURES: []const TextureMeta.TexInf = &.{ quantTex, quantDepthTex, quantDebugTex, quantDebugDepthTex };

// Passes
pub const PASSES: []const Pass = &.{
    compCull,
    mainCull,
    debugCull,
    frustum,

    // comp,
    // main,
    // debug,

    editorGrid,
};

// Cull Test
pub const compCull: Pass = .{
    .name = "Comp",
    .shaderIds = &.{sc.cullTestComp.id}, // sc.quantComp.id // sc.cullTestComp.id
    .typ = Pass.createCompute(.{
        .workgroups = .{ .x = 1, .y = 1, .z = 1 },
    }),
    .bufUses = &.{
        BufferUse.init(indirectSB.id, .ComputeShader, .ShaderReadWrite, 0),
        BufferUse.init(objectSB.id, .ComputeShader, .ShaderRead, 1),
    },
};

const mainCull: Pass = .{
    .name = "Main",
    .shaderIds = &.{ sc.cullTestMesh.id, sc.cullTestFrag.id }, // sc.quantMesh.id, sc.quantFrag.id // sc.cullTestMesh.id, sc.cullTestFrag.id
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.ClassicTyp.taskMeshData(.{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = .{ .id = indirectSB.id, .offset = 0 },
        }),
        .mainTexId = quantTex.id,
        .colorAtts = &.{Attachment.init(quantTex.id, .ColorAtt, .ColorAttReadWrite, true)},
        .depthAtt = Attachment.init(quantDepthTex.id, .EarlyFragTest, .DepthStencilWrite, true),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_LESS,
            .cullMode = vk.VK_CULL_MODE_NONE,
            // .polygonMode = vk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
            // .lineWidth = 2.0,
            // .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        },
    }),
    .bufUses = &.{
        BufferUse.init(indirectSB.id, .DrawIndirect, .IndirectRead, null),
        BufferUse.init(cameraUB.id, .FragShader, .ShaderRead, 0),
        BufferUse.init(cameraUB.id, .FragShader, .ShaderRead, 1),
    },
};

const debugCull: Pass = .{
    .name = "Debug",
    .shaderIds = &.{ sc.cullTestMesh.id, sc.cullTestFrag.id }, // sc.quantMesh.id, sc.quantFrag.id // sc.cullTestMesh.id, sc.cullTestFrag.id
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.ClassicTyp.taskMeshData(.{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = .{ .id = indirectSB.id, .offset = 0 },
        }),
        .mainTexId = quantDebugTex.id,
        .colorAtts = &.{Attachment.init(quantDebugTex.id, .ColorAtt, .ColorAttReadWrite, true)},
        .depthAtt = Attachment.init(quantDebugDepthTex.id, .EarlyFragTest, .DepthStencilWrite, true),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_LESS,
            .cullMode = vk.VK_CULL_MODE_NONE,
            // .polygonMode = vk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
            // .lineWidth = 2.0,
            // .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        },
    }),
    .bufUses = &.{
        BufferUse.init(indirectSB.id, .DrawIndirect, .IndirectRead, null),
        BufferUse.init(camera2UB.id, .FragShader, .ShaderRead, 0),
        BufferUse.init(cameraUB.id, .FragShader, .ShaderRead, 1),
    },
};

// Normal Pass
pub const comp: Pass = .{
    .name = "Comp",
    .shaderIds = &.{sc.quantComp.id}, // sc.quantComp.id // sc.cullTestComp.id
    .typ = Pass.createCompute(.{
        .workgroups = .{ .x = 1, .y = 1, .z = 1 },
    }),
    .bufUses = &.{
        BufferUse.init(indirectSB.id, .ComputeShader, .ShaderReadWrite, 0),
        BufferUse.init(objectSB.id, .ComputeShader, .ShaderRead, 1),
    },
};

const main: Pass = .{
    .name = "Main",
    .shaderIds = &.{ sc.quantMesh.id, sc.quantFrag.id }, // sc.quantMesh.id, sc.quantFrag.id // sc.cullTestMesh.id, sc.cullTestFrag.id
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.ClassicTyp.taskMeshData(.{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = .{ .id = indirectSB.id, .offset = 0 },
        }),
        .mainTexId = quantTex.id,
        .colorAtts = &.{Attachment.init(quantTex.id, .ColorAtt, .ColorAttReadWrite, true)},
        .depthAtt = Attachment.init(quantDepthTex.id, .EarlyFragTest, .DepthStencilWrite, true),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_LESS,
            .cullMode = vk.VK_CULL_MODE_NONE,
            // .polygonMode = vk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
            // .lineWidth = 2.0,
            // .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        },
    }),
    .bufUses = &.{
        BufferUse.init(indirectSB.id, .DrawIndirect, .IndirectRead, null),
        BufferUse.init(cameraUB.id, .FragShader, .ShaderRead, 0),
        BufferUse.init(cameraUB.id, .FragShader, .ShaderRead, 1),
    },
};

const debug: Pass = .{
    .name = "Debug",
    .shaderIds = &.{ sc.quantMesh.id, sc.quantFrag.id }, // sc.quantMesh.id, sc.quantFrag.id // sc.cullTestMesh.id, sc.cullTestFrag.id
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.ClassicTyp.taskMeshData(.{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = .{ .id = indirectSB.id, .offset = 0 },
        }),
        .mainTexId = quantDebugTex.id,
        .colorAtts = &.{Attachment.init(quantDebugTex.id, .ColorAtt, .ColorAttReadWrite, true)},
        .depthAtt = Attachment.init(quantDebugDepthTex.id, .EarlyFragTest, .DepthStencilWrite, true),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_LESS,
            .cullMode = vk.VK_CULL_MODE_NONE,
            // .polygonMode = vk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
            // .lineWidth = 2.0,
            // .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        },
    }),
    .bufUses = &.{
        BufferUse.init(indirectSB.id, .DrawIndirect, .IndirectRead, null),
        BufferUse.init(camera2UB.id, .FragShader, .ShaderRead, 0),
        BufferUse.init(cameraUB.id, .FragShader, .ShaderRead, 1),
    },
};

pub const frustum: Pass = .{
    .name = "Frustum",
    .shaderIds = &.{ sc.frustumMesh.id, sc.quantFrag.id },
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.ClassicTyp.taskMeshData(.{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
        }),
        .mainTexId = quantDebugTex.id,
        .colorAtts = &.{Attachment.init(quantDebugTex.id, .ColorAtt, .ColorAttReadWrite, false)},
        .depthAtt = Attachment.init(quantDebugDepthTex.id, .EarlyFragTest, .DepthStencilWrite, false),
        .renderState = .{
            .depthTest = vk.VK_FALSE,
            .depthWrite = vk.VK_FALSE,
            .lineWidth = 2.0,
        },
    }),
    .bufUses = &.{
        BufferUse.init(cameraUB.id, .MeshShader, .ShaderRead, 0),
        BufferUse.init(camera2UB.id, .MeshShader, .ShaderRead, 1),
    },
};

pub const editorGrid: Pass = .{
    .name = "Editor-Grid",
    .shaderIds = &.{ sc.editorGridMesh.id, sc.editorGridFrag.id },
    .typ = Pass.createClassic(.{
        .classicTyp = Pass.ClassicTyp.taskMeshData(.{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
        }),
        .mainTexId = quantDebugTex.id,
        .colorAtts = &.{Attachment.init(quantDebugTex.id, .ColorAtt, .ColorAttReadWrite, false)},
        .depthAtt = Attachment.init(quantDebugDepthTex.id, .EarlyFragTest, .DepthStencilWrite, false),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_LESS,
            .cullMode = vk.VK_CULL_MODE_NONE,
        },
    }),
    .bufUses = &.{
        BufferUse.init(camera2UB.id, .MeshShader, .ShaderRead, 0),
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
