const AttachmentUse = @import("../render/types/pass/AttachmentUse.zig").AttachmentUse;
const TexId = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexId;
const BufId = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufId;
const TextureUse = @import("../render/types/pass/TextureUse.zig").TextureUse;
const BufferUse = @import("../render/types/pass/BufferUse.zig").BufferUse;
const PassDef = @import("../render/types/pass/PassDef.zig").PassDef;
const vk = @import("../.modules/vk.zig").c;
const sc = @import("shaderConfig.zig");

pub fn ImGuiPass(def: struct {
    name: []const u8,
    colorAtt: TexId,
    vertexBuf: BufId,
    indexBuf: BufId,
}) PassDef {
    return PassDef.Graphics(.{
        .name = def.name,
        .execution = .{ .vertices = 0, .instances = 1, .indexCount = 0, .mainTexId = def.colorAtt },
        .vertex = sc.imguiVert,
        .fragment = sc.imguiFrag,
        .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .Attachment, false)},
        .renderState = .{
            .cullMode = vk.VK_CULL_MODE_NONE,
            .depthTest = vk.VK_FALSE,
            .depthWrite = vk.VK_FALSE,
            .colorBlend = vk.VK_TRUE,
            .colorBlendEquation = .{
                .srcColor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
                .dstColor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
                .srcAlpha = vk.VK_BLEND_FACTOR_ONE,
                .dstAlpha = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            },
        },
        .vertexBuffers = &.{.{ .bufId = def.vertexBuf, .binding = 0, .stride = 20 }},
        .indexBuffer = .{ .bufId = def.indexBuf, .indexType = vk.VK_INDEX_TYPE_UINT16 },
        .vertexAttributes = &.{
            .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 0 },
            .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 8 },
            .{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = 16 },
        },
    });
}

pub fn CompRayMarch(
    def: struct {
        name: []const u8,
        outputTex: TexId,
        entityBuf: BufId,
        camBuf: BufId,
        readbackBuf: BufId,
        debugTex: TexId,
    },
) PassDef {
    return PassDef.ComputeOnImg(.{
        .name = def.name,
        .execution = .{ .workgroups = .{ .x = 8, .y = 8, .z = 1 }, .mainTexId = def.outputTex },
        .compute = sc.t1Comp,
        .bufUses = &.{
            BufferUse.init(def.entityBuf, .Compute, .ShaderRead, 0),
            BufferUse.init(def.camBuf, .Compute, .UniformRead, 1),
            BufferUse.init(def.readbackBuf, .Compute, .ShaderWrite, 3),
        },
        .texUses = &.{
            TextureUse.init(def.outputTex, .Compute, .ShaderWrite, .General, 2, .Storage),
            TextureUse.init(def.debugTex, .Compute, .ShaderRead, .General, 4, .Storage),
        },
    });
}

pub fn EditorGrid(
    def: struct {
        name: []const u8,
        colorAtt: TexId,
        depthAtt: TexId,
        camBuf: BufId,
    },
) PassDef {
    return PassDef.Mesh(.{
        .name = def.name,
        .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 }, .mainTexId = def.colorAtt },
        .mesh = sc.editorGridMesh,
        .fragment = sc.editorGridFrag,
        .bufUses = &.{
            BufferUse.init(def.camBuf, .Mesh, .UniformRead, 0),
        },
        .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .Attachment, false)},
        .depthAtt = AttachmentUse.init(def.depthAtt, .EarlyFragTest, .DepthStencilWrite, .Attachment, false),
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
        colorAtt: TexId,
        depthAtt: TexId,
        frustumCamBuf: BufId, // Maybe swapped
        viewCamBuf: BufId, // Maybe swapped
    },
) PassDef {
    return PassDef.Mesh(.{
        .name = def.name,
        .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 }, .mainTexId = def.colorAtt },
        .mesh = sc.frustumMesh,
        .fragment = sc.quantFrag,
        .bufUses = &.{
            BufferUse.init(def.frustumCamBuf, .Mesh, .UniformRead, 0),
            BufferUse.init(def.viewCamBuf, .Mesh, .UniformRead, 1),
        },
        .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .Attachment, false)},
        .depthAtt = AttachmentUse.init(def.depthAtt, .EarlyFragTest, .DepthStencilWrite, .Attachment, false),
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
) PassDef {
    return PassDef.Compute(.{
        .name = def.name,
        .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } },
        .compute = sc.quantComp,
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .Compute, .ShaderReadWrite, 0),
            BufferUse.init(def.entityBuf, .Compute, .ShaderRead, 1),
        },
    });
}

pub fn QuantGrid(
    def: struct {
        name: []const u8,
        colorAtt: TexId,
        depthAtt: TexId,
        indirectBuf: BufId,
        viewCam: BufId, // Maybe swapped
        cullCam: BufId, // Maybe swapped
    },
) PassDef {
    return PassDef.MeshIndirect(.{
        .name = def.name,
        .execution = .{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = def.indirectBuf,
            .indirectBufOffset = 0,
            .mainTexId = def.colorAtt,
        },
        .mesh = sc.quantGrid,
        .fragment = sc.quantFrag,
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
            BufferUse.init(def.viewCam, .Fragment, .UniformRead, 0),
            BufferUse.init(def.cullCam, .Fragment, .UniformRead, 1),
        },
        .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .Attachment, true)},
        .depthAtt = AttachmentUse.init(def.depthAtt, .EarlyFragTest, .DepthStencilWrite, .Attachment, true),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_LESS,
            .cullMode = vk.VK_CULL_MODE_NONE,
        },
    });
}

pub fn QuantPlane(
    def: struct {
        name: []const u8,
        colorAtt: TexId,
        depthAtt: TexId,
        indirectBuf: BufId,
        viewCam: BufId, // Maybe swapped
        cullCam: BufId, // Maybe swapped
    },
) PassDef {
    return PassDef.MeshIndirect(.{
        .name = def.name,
        .execution = .{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = def.indirectBuf,
            .indirectBufOffset = 0,
            .mainTexId = def.colorAtt,
        },
        .mesh = sc.quantPlane,
        .fragment = sc.quantFrag,
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
            BufferUse.init(def.viewCam, .Fragment, .UniformRead, 0),
            BufferUse.init(def.cullCam, .Fragment, .UniformRead, 1),
        },
        .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .Attachment, true)},
        .depthAtt = AttachmentUse.init(def.depthAtt, .EarlyFragTest, .DepthStencilWrite, .Attachment, true),
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
) PassDef {
    return PassDef.Compute(.{
        .name = def.name,
        .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } },
        .compute = sc.cullTestComp,
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .Compute, .ShaderReadWrite, 0),
            BufferUse.init(def.entityBuf, .Compute, .ShaderRead, 1),
        },
    });
}

pub fn Cull(
    def: struct {
        name: []const u8,
        colorAtt: TexId,
        depthAtt: TexId,
        indirectBuf: BufId,
        viewCam: BufId, // Maybe swapped
        cullCam: BufId, // Maybe swapped
    },
) PassDef {
    return PassDef.MeshIndirect(.{
        .name = def.name,
        .execution = .{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = def.indirectBuf,
            .indirectBufOffset = 0,
            .mainTexId = def.colorAtt,
        },
        .mesh = sc.cullTestMesh,
        .fragment = sc.cullTestFrag,
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
            BufferUse.init(def.viewCam, .Fragment, .UniformRead, 0),
            BufferUse.init(def.cullCam, .Fragment, .UniformRead, 1),
        },
        .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .Attachment, true)},
        .depthAtt = AttachmentUse.init(def.depthAtt, .EarlyFragTest, .DepthStencilWrite, .Attachment, true),
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
