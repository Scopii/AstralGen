const Attachment = @import("../render/types/base/Pass.zig").Attachment;
const TextureUse = @import("../render/types/base/Pass.zig").TextureUse;
const BufferUse = @import("../render/types/base/Pass.zig").BufferUse;
const TextureMeta = @import("../render/types/res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../render/types/res/BufferMeta.zig").BufferMeta;
const CameraData = @import("../camera/CameraSys.zig").CamData;
const Pass = @import("../render/types/base/Pass.zig").Pass;
const vhT = @import("../render/help/Types.zig");
const vk = @import("../.modules/vk.zig").c;
const sc = @import("shaderConfig.zig");
const ShaderId = @import("../shader/ShaderSys.zig").ShaderId;
const BufId = BufferMeta.BufId;
const TexId = TextureMeta.TexId;

const GpuObjectData = @import("../render/help/Types.zig").GpuObjectData;

pub fn CompRayMarch(
    def: struct {
        name: []const u8,
        rayTex: TexId,
        entityBuf: BufId,
        camBuf: BufId,
        readbackBuf: BufId,
    },
) Pass {
    return Pass.init(.{
        .name = def.name,
        .execution = .{ .computeOnImg = .{ .workgroups = .{ .x = 8, .y = 8, .z = 1 }, .mainTexId = def.rayTex } },
        .shaderIds = &.{sc.t1Comp.id},
        .bufUses = &.{
            BufferUse.init(def.entityBuf, .ComputeShader, .ShaderRead, 0),
            BufferUse.init(def.camBuf, .ComputeShader, .ShaderRead, 1),
            BufferUse.init(def.readbackBuf, .ComputeShader, .ShaderWrite, 3),
        },
        .texUses = &.{
            TextureUse.init(def.rayTex, .ComputeShader, .ShaderWrite, .General, 2),
        },
    });
}

pub fn EditorGrid(
    def: struct {
        name: []const u8,
        debugTex: TexId,
        debugDepthTex: TexId,
        camBuf: BufId,
    },
) Pass {
    return Pass.init(.{
        .name = def.name,
        .execution = .{ .taskOrMesh = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 }, .mainTexId = def.debugTex } },
        .shaderIds = &.{ sc.editorGridMesh.id, sc.editorGridFrag.id },
        .bufUses = &.{
            BufferUse.init(def.camBuf, .MeshShader, .ShaderRead, 0),
        },
        .colorAtts = &.{Attachment.init(def.debugTex, .ColorAtt, .ColorAttReadWrite, false)},
        .depthAtt = Attachment.init(def.debugDepthTex, .EarlyFragTest, .DepthStencilWrite, false),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_LESS,
            .cullMode = vk.VK_CULL_MODE_NONE,
        },
    });
}

pub fn FrustumView(
    def: struct {
        name: []const u8,
        debugTex: TexId,
        debugDepthTex: TexId,
        frustumCamBuf: BufId, // Maybe swapped
        viewCamBuf: BufId, // Maybe swapped
    },
) Pass {
    return Pass.init(.{
        .name = def.name,
        .execution = .{ .taskOrMesh = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 }, .mainTexId = def.debugTex } },
        .shaderIds = &.{ sc.frustumMesh.id, sc.quantFrag.id },
        .bufUses = &.{
            BufferUse.init(def.frustumCamBuf, .MeshShader, .ShaderRead, 0),
            BufferUse.init(def.viewCamBuf, .MeshShader, .ShaderRead, 1),
        },
        .colorAtts = &.{Attachment.init(def.debugTex, .ColorAtt, .ColorAttReadWrite, false)},
        .depthAtt = Attachment.init(def.debugDepthTex, .EarlyFragTest, .DepthStencilWrite, false),
        .renderState = .{
            .depthTest = vk.VK_FALSE,
            .depthWrite = vk.VK_FALSE,
            .lineWidth = 2.0,
        },
    });
}

pub fn QuantComp(
    def: struct {
        name: []const u8,
        indirectBuf: BufId,
        entityBuf: BufId,
    },
) Pass {
    return Pass.init(.{
        .name = def.name,
        .execution = .{ .compute = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } } },
        .shaderIds = &.{sc.quantComp.id},
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .ComputeShader, .ShaderReadWrite, 0),
            BufferUse.init(def.entityBuf, .ComputeShader, .ShaderRead, 1),
        },
    });
}

pub fn Quant(
    def: struct {
        name: []const u8,
        debugTex: TexId,
        debugDepthTex: TexId,
        indirectBuf: BufId,
        viewCam: BufId, // Maybe swapped
        cullCam: BufId, // Maybe swapped
    },
) Pass {
    return Pass.init(.{
        .name = def.name,
        .execution = .{
            .taskOrMeshIndirect = .{
                .workgroups = .{ .x = 1, .y = 1, .z = 1 },
                .indirectBuf = def.indirectBuf,
                .indirectBufOffset = 0,
                .mainTexId = def.debugTex,
            },
        },
        .shaderIds = &.{ sc.quantMesh.id, sc.quantFrag.id },
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
            BufferUse.init(def.viewCam, .FragShader, .ShaderRead, 0),
            BufferUse.init(def.cullCam, .FragShader, .ShaderRead, 1),
        },
        .colorAtts = &.{Attachment.init(def.debugTex, .ColorAtt, .ColorAttReadWrite, true)},
        .depthAtt = Attachment.init(def.debugDepthTex, .EarlyFragTest, .DepthStencilWrite, true),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_LESS,
            .cullMode = vk.VK_CULL_MODE_NONE,
        },
    });
}

pub fn CullComp(
    def: struct {
        name: []const u8,
        indirectBuf: BufId,
        entityBuf: BufId,
    },
) Pass {
    return Pass.init(.{
        .name = def.name,
        .execution = .{ .compute = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } } },
        .shaderIds = &.{sc.cullTestComp.id},
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .ComputeShader, .ShaderReadWrite, 0),
            BufferUse.init(def.entityBuf, .ComputeShader, .ShaderRead, 1),
        },
    });
}

pub fn Cull(
    def: struct {
        name: []const u8,
        mainTex: TexId,
        mainDepthTex: TexId,
        indirectBuf: BufId,
        viewCam: BufId, // Maybe swapped
        cullCam: BufId, // Maybe swapped
    },
) Pass {
    return Pass.init(.{
        .name = def.name,
        .execution = .{
            .taskOrMeshIndirect = .{
                .workgroups = .{ .x = 1, .y = 1, .z = 1 },
                .indirectBuf = def.indirectBuf,
                .indirectBufOffset = 0,
                .mainTexId = def.mainTex,
            },
        },
        .shaderIds = &.{ sc.cullTestMesh.id, sc.cullTestFrag.id },
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
            BufferUse.init(def.viewCam, .FragShader, .ShaderRead, 0),
            BufferUse.init(def.cullCam, .FragShader, .ShaderRead, 1),
        },
        .colorAtts = &.{Attachment.init(def.mainTex, .ColorAtt, .ColorAttReadWrite, true)},
        .depthAtt = Attachment.init(def.mainDepthTex, .EarlyFragTest, .DepthStencilWrite, true),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_LESS,
            .cullMode = vk.VK_CULL_MODE_NONE,
        },
    });
}

// OLD PASSES

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
