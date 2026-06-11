const VertexBufferUse = @import("../render/types/pass/VertexBufferUse.zig").VertexBufferUse;
const VertexAttribute = @import("../render/types/pass/VertexAttribute.zig").VertexAttribute;
const IndexBufferUse = @import("../render/types/pass/IndexBufferUse.zig").IndexBufferUse;
const AttachmentUse = @import("../render/types/pass/AttachmentUse.zig").AttachmentUse;
const TextureUse = @import("../render/types/pass/TextureUse.zig").TextureUse;
const BufferUse = @import("../render/types/pass/BufferUse.zig").BufferUse;
const PassDef = @import("../render/types/pass/PassDef.zig").PassDef;
const vk = @import("../.modules/vk.zig").c;
const sc = @import("shaderConfig.zig");

const TextureEnum = @import("../frameBuild/enums.zig").TextureEnum;
const BufferEnum = @import("../frameBuild/enums.zig").BufferEnum;
const PassEnum = @import("../frameBuild/enums.zig").PassEnum;

const TextureLink = @import("../frameBuild/components.zig").TextureLink;
const BufferLink = @import("../frameBuild/components.zig").BufferLink;

/// MIGHT HAVE TO CHANGE PASS.outputTexId TO .out NOT .in
///
pub fn DepthView(def: struct {
    name: PassEnum,
    outputTex: TextureLink,
    depthTex: TextureLink,
    camBuf: BufferLink,
}) PassDef {
    return PassDef.ComputeOnImg(.{
        .name = def.name,
        .outputTexId = def.outputTex.in,
        .execution = .{ .workgroups = .{ .x = 8, .y = 8, .z = 1 }, .mainTexId = def.outputTex.in },
        .compute = sc.depthViewComp,
        .bufUses = &.{
            BufferUse.init(def.camBuf, .Compute, .UniformRead, 3),
        },
        .texUses = &.{
            TextureUse.init(def.outputTex, .Compute, .StorageWrite, 0),
            TextureUse.init(def.depthTex, .Compute, .SampledRead, 1),
        },
    });
}

pub fn ImGuiPass(def: struct {
    name: PassEnum,
    colorAtt: TextureLink,
    vertexBuf: BufferEnum,
    indexBuf: BufferEnum,
}) PassDef {
    return PassDef.Graphics(.{
        .name = def.name,
        .outputTexId = null,
        .execution = .{ .vertices = 0, .instances = 1, .indexCount = 0, .mainTexId = def.colorAtt.in },
        .vertex = sc.imguiVert,
        .fragment = sc.imguiFrag,
        .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
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
        .vertexBuffers = &.{VertexBufferUse.init(def.vertexBuf, 0, 20, vk.VK_VERTEX_INPUT_RATE_VERTEX)},
        .indexBuffer = IndexBufferUse.init(def.indexBuf, vk.VK_INDEX_TYPE_UINT16),
        .vertexAttributes = &.{
            VertexAttribute{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 0 },
            VertexAttribute{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 8 },
            VertexAttribute{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = 16 },
        },
    });
}

pub fn CompRayMarch(
    def: struct {
        name: PassEnum,
        outputTex: TextureLink,
        entityBuf: BufferLink,
        camBuf: BufferLink,
        readbackBuf: BufferLink,
        debugTex: TextureLink,
    },
) PassDef {
    return PassDef.ComputeOnImg(.{
        .name = def.name,
        .outputTexId = def.outputTex.in,
        .execution = .{ .workgroups = .{ .x = 8, .y = 8, .z = 1 }, .mainTexId = def.outputTex.in },
        .compute = sc.t1Comp,
        .bufUses = &.{
            BufferUse.init(def.entityBuf, .Compute, .StorageRead, 0),
            BufferUse.init(def.camBuf, .Compute, .UniformRead, 1),
            BufferUse.init(def.readbackBuf, .Compute, .StorageWrite, 3),
        },
        .texUses = &.{
            TextureUse.init(def.outputTex, .Compute, .StorageWrite, 2),
            TextureUse.init(def.debugTex, .Compute, .StorageRead, 4),
        },
    });
}

pub fn EditorGrid(
    def: struct {
        name: PassEnum,
        colorAtt: TextureLink,
        depthAtt: TextureLink,
        camBuf: BufferLink,
    },
) PassDef {
    return PassDef.Mesh(.{
        .name = def.name,
        .outputTexId = def.colorAtt.in,
        .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 }, .mainTexId = def.colorAtt.in },
        .mesh = sc.editorGridMesh,
        .fragment = sc.editorGridFrag,
        .bufUses = &.{
            BufferUse.init(def.camBuf, .Mesh, .UniformRead, 0),
        },
        .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
        .depthAtt = AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, null),
        .renderState = .{
            .colorBlend = vk.VK_FALSE,
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_GREATER,
            .cullMode = vk.VK_CULL_MODE_NONE,
        },
    });
}

pub fn FrustumView(
    def: struct {
        name: PassEnum,
        colorAtt: TextureLink,
        depthAtt: TextureLink,
        renderCam: BufferLink, 
        viewCam: BufferLink, 
    },
) PassDef {
    return PassDef.Mesh(.{
        .name = def.name,
        .outputTexId = def.colorAtt.in,
        .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 }, .mainTexId = def.colorAtt.in },
        .mesh = sc.frustumMesh,
        .fragment = sc.quantFrag,
        .bufUses = &.{
            BufferUse.init(def.renderCam, .Mesh, .UniformRead, 0),
            BufferUse.init(def.viewCam, .Mesh, .UniformRead, 1),
        },
        .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
        .depthAtt = AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, null),
        .renderState = .{
            .depthTest = vk.VK_FALSE, // Depth Currently not in Use
            .depthWrite = vk.VK_FALSE, // Depth Currently not in Use
            .lineWidth = 2.0,
        },
    });
}

pub fn QuantComp(
    def: struct {
        name: PassEnum,
        indirectBuf: BufferLink,
        entityBuf: BufferLink,
    },
) PassDef {
    return PassDef.Compute(.{
        .name = def.name,
        .outputTexId = null,
        .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } },
        .compute = sc.quantComp,
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .Compute, .StorageReadWrite, 0),
            BufferUse.init(def.entityBuf, .Compute, .StorageRead, 1),
        },
    });
}

pub fn QuantGrid(
    def: struct {
        name: PassEnum,
        colorAtt: TextureLink,
        depthAtt: TextureLink,
        indirectBuf: BufferLink,
        viewCam: BufferLink,
        renderCam: BufferLink,
    },
) PassDef {
    return PassDef.MeshIndirect(.{
        .name = def.name,
        .outputTexId = def.colorAtt.in,
        .execution = .{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = def.indirectBuf.in,
            .indirectBufOffset = 0,
            .mainTexId = def.colorAtt.in,
        },
        .mesh = sc.quantGrid,
        .fragment = sc.quantFrag,
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
            BufferUse.init(def.viewCam, .Fragment, .UniformRead, 0),
            BufferUse.init(def.renderCam, .Fragment, .UniformRead, 1),
        },
        .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
        .depthAtt = AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, .{ .depthStencil = .{ .depth = 0.0, .stencil = 0 } }),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_GREATER,
            .cullMode = vk.VK_CULL_MODE_NONE,
        },
    });
}

pub fn QuantPlane(
    def: struct {
        name: PassEnum,
        colorAtt: TextureLink,
        depthAtt: TextureLink,
        indirectBuf: BufferLink,
        viewCam: BufferLink,
        renderCam: BufferLink,
    },
) PassDef {
    return PassDef.MeshIndirect(.{
        .name = def.name,
        .outputTexId = def.colorAtt.in,
        .execution = .{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = def.indirectBuf.in,
            .indirectBufOffset = 0,
            .mainTexId = def.colorAtt.in,
        },
        .mesh = sc.quantPlane,
        .fragment = sc.quantFrag,
        .bufUses = &.{
            BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
            BufferUse.init(def.viewCam, .Fragment, .UniformRead, 0),
            BufferUse.init(def.renderCam, .Fragment, .UniformRead, 1),
        },
        .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
        .depthAtt = AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, .{ .depthStencil = .{ .depth = 0.0, .stencil = 0 } }),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_GREATER,
            .cullMode = vk.VK_CULL_MODE_NONE,
        },
    });
}

// pub fn CullComp(
//     def: struct {
//         name: []const u8,
//         indirectBuf: BufferLink,
//         entityBuf: BufferLink,
//     },
// ) PassDef {
//     return PassDef.Compute(.{
//         .name = def.name,
//         .outputTexId = null,
//         .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } },
//         .compute = sc.cullTestComp,
//         .bufUses = &.{
//             BufferUse.init(def.indirectBuf, .Compute, .ShaderReadWrite, 0),
//             BufferUse.init(def.entityBuf, .Compute, .ShaderRead, 1),
//         },
//     });
// }

// pub fn Cull(
//     def: struct {
//         name: []const u8,
//         colorAtt: TextureLink,
//         depthAtt: TextureLink,
//         indirectBuf: BufferLink,
//         viewCam: BufferLink, // Maybe swapped
//         cullCam: BufferLink, // Maybe swapped
//     },
// ) PassDef {
//     return PassDef.MeshIndirect(.{
//         .name = def.name,
//         .outputTexId = def.colorAtt,
//         .execution = .{
//             .workgroups = .{ .x = 1, .y = 1, .z = 1 },
//             .indirectBuf = def.indirectBuf,
//             .indirectBufOffset = 0,
//             .mainTexId = def.colorAtt,
//         },
//         .mesh = sc.cullTestMesh,
//         .fragment = sc.cullTestFrag,
//         .bufUses = &.{
//             BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
//             BufferUse.init(def.viewCam, .Fragment, .UniformRead, 0),
//             BufferUse.init(def.cullCam, .Fragment, .UniformRead, 1),
//         },
//         .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .Attachment, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
//         .depthAtt = AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, .Attachment, .{ .depthStencil = .{ .depth = 0.0, .stencil = 0 } }),
//         .renderState = .{
//             .depthTest = vk.VK_TRUE,
//             .depthWrite = vk.VK_TRUE,
//             .depthCompare = vk.VK_COMPARE_OP_GREATER,
//             .cullMode = vk.VK_CULL_MODE_NONE,
//         },
//     });
// }

// OLD PASSES

// pub const grapTex = Texture.create(.{ .id = .{ .val = 2 }, .mem = .Gpu, .typ = .Color, .width = 300, .height = 300 });
// pub const meshTex = Texture.create(.{ .id = .{ .val = 3 }, .mem = .Gpu, .typ = .Color, .width = 100, .height = 100 });
// pub const taskTex = Texture.create(.{ .id = .{ .val = 4 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1920 });
// pub const testTex = Texture.create(.{ .id = .{ .val = 5 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1920 });
// pub const depthTex = Texture.create(.{ .id = .{ .val = 11 }, .mem = .Gpu, .typ = .Depth, .width = 1920, .height = 1920 });
// pub const textures: []const Texture.TexInf = &.{ compTex, grapTex, meshTex, taskTex, testTex, depthTex };

// pub const passes: []const Pass = &.{  taskTest, gridTest, grapTest, meshTest, indirectCompTest, indirectTaskTest };

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
