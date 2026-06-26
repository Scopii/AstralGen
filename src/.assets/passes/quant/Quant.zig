const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

// pub fn QuantGrid(
//     def: struct {
//         string: []const u8,
//         colorAtt: p.TextureLink,
//         depthAtt: p.TextureLink,
//         indirectBuf: p.BufferLink,
//         viewCam: p.BufferLink,
//         renderCam: p.BufferLink,
//     },
// ) p.PassDef {
//     return p.PassDef.MeshIndirect(.{
//         .name = def.string,
//         .outputTexId = def.colorAtt.in,
//         .execution = .{
//             .workgroups = .{ .x = 1, .y = 1, .z = 1 },
//             .indirectBuf = def.indirectBuf.in,
//             .indirectBufOffset = 0,
//         },
//         .mesh = sc.quantGrid,
//         .fragment = sc.quantFrag,
//         .bufUses = &.{
//             p.BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
//             p.BufferUse.init(def.viewCam, .Fragment, .UniformRead, 0),
//             p.BufferUse.init(def.renderCam, .Fragment, .UniformRead, 1),
//         },
//         .colorAtts = &.{p.AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
//         .depthAtt = p.AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, .{ .depthStencil = .{ .depth = 0.0, .stencil = 0 } }),
//         .renderState = .{
//             .depthTest = .True,
//             .depthWrite = .True,
//             .depthCompare = .Greater,
//             .cullMode = .None,
//         },
//     });
// }

// pub fn QuantPlane(
//     def: struct {
//         string: []const u8,
//         colorAtt: p.TextureLink,
//         depthAtt: p.TextureLink,
//         indirectBuf: p.BufferLink,
//         viewCam: p.BufferLink,
//         renderCam: p.BufferLink,
//     },
// ) p.PassDef {
//     return p.PassDef.MeshIndirect(.{
//         .name = def.string,
//         .outputTexId = def.colorAtt.in,
//         .execution = .{
//             .workgroups = .{ .x = 1, .y = 1, .z = 1 },
//             .indirectBuf = def.indirectBuf.in,
//             .indirectBufOffset = 0,
//         },
//         .mesh = sc.quantPlane,
//         .fragment = sc.quantFrag,
//         .bufUses = &.{
//             p.BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
//             p.BufferUse.init(def.viewCam, .Fragment, .UniformRead, 0),
//             p.BufferUse.init(def.renderCam, .Fragment, .UniformRead, 1),
//         },
//         .colorAtts = &.{p.AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
//         .depthAtt = p.AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, .{ .depthStencil = .{ .depth = 0.0, .stencil = 0 } }),
//         .renderState = .{
//             .depthTest = .True,
//             .depthWrite = .True,
//             .depthCompare = .Greater,
//             .cullMode = .None,
//         },
//     });
// }

pub const quantGridPass = QuantTemplate(.{
    .string = "QuantGridMain",
    .meshShader = sc.quantGrid,
    .fragShader = sc.quantFrag,
    .colorAtt = .{ .in = "GridTex" },
    .depthAtt = .{ .in = "GridDepthTex" },
    .indirectBuf = .{ .in = "QuantIndirectOutputSB" },
    .viewCam = .{ .in = "MainCamUB" },
    .renderCam = .{ .in = "MainCamUB" },
});

pub const quantGridDebugPass = QuantTemplate(.{
    .string = "QuantGridDebug",
    .meshShader = sc.quantGrid,
    .fragShader = sc.quantFrag,
    .colorAtt = .{ .in = "DebugGridInputTex", .out = "DebugGridOutputTex" },
    .depthAtt = .{ .in = "DebugGridDepthTex" },
    .indirectBuf = .{ .in = "QuantIndirectOutputSB" },
    .viewCam = .{ .in = "DebugCamUB" },
    .renderCam = .{ .in = "MainCamUB" },
});

pub const quantPlanePass = QuantTemplate(.{
    .string = "QuantPlaneMain",
    .meshShader = sc.quantPlane,
    .fragShader = sc.quantFrag,
    .colorAtt = .{ .in = "PlaneTex" },
    .depthAtt = .{ .in = "PlaneDepthTex" },
    .indirectBuf = .{ .in = "QuantIndirectOutputSB" },
    .viewCam = .{ .in = "MainCamUB" },
    .renderCam = .{ .in = "MainCamUB" },
});

pub const quantPlaneDebugPass = QuantTemplate(.{
    .string = "QuantPlaneDebug",
    .meshShader = sc.quantPlane,
    .fragShader = sc.quantFrag,
    .colorAtt = .{ .in = "DebugPlaneInputTex", .out = "DebugPlaneOutputTex" },
    .depthAtt = .{ .in = "DebugPlaneDepthTex" },
    .indirectBuf = .{ .in = "QuantIndirectOutputSB" },
    .viewCam = .{ .in = "DebugCamUB" },
    .renderCam = .{ .in = "MainCamUB" },
});

pub fn QuantTemplate(
    def: struct {
        meshShader: p.ShaderInf,
        fragShader: p.ShaderInf,
        string: []const u8,
        colorAtt: p.TextureStringLink,
        depthAtt: p.TextureStringLink,
        indirectBuf: p.BufferStringLink,
        viewCam: p.BufferStringLink,
        renderCam: p.BufferStringLink,
    },
) p.PassDefinition {
    return p.PassDefinition.init(.{
        .name = def.string,
        .outputTex = def.colorAtt.in,
        .passAttributes = &.{
            p.PassAttrib.exec(.{
                .taskOrMeshIndirect = .{
                    .workgroups = .{ .x = 1, .y = 1, .z = 1 },
                    .indirectBuf = def.indirectBuf.in,
                    .indirectBufOffset = 0,
                },
            }),
            //
            p.PassAttrib.shader(def.meshShader),
            p.PassAttrib.shader(def.fragShader),
            //
            p.PassAttrib.color(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } }),
            p.PassAttrib.depth(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, .{ .depthStencil = .{ .depth = 0.0, .stencil = 0 } }),
            //
            p.PassAttrib.buf(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
            p.PassAttrib.buf(def.viewCam, .Fragment, .UniformRead, 0),
            p.PassAttrib.buf(def.renderCam, .Fragment, .UniformRead, 1),
            //
            p.PassAttrib.state(.{ .depthTest = .True }),
            p.PassAttrib.state(.{ .depthWrite = .True }),
            p.PassAttrib.state(.{ .depthCompare = .Greater }),
            p.PassAttrib.state(.{ .cullMode = .None }),
        },
    });
}
