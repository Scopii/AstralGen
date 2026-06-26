const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

// pub fn EditorGrid(
//     def: struct {
//         string: []const u8,
//         colorAtt: p.TextureLink,
//         depthAtt: p.TextureLink,
//         camBuf: p.BufferLink,
//     },
// ) p.PassDef {
//     return p.PassDef.Mesh(.{
//         .name = def.string,
//         .outputTexId = def.colorAtt.in,
//         .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } },
//         .mesh = sc.editorGridMesh,
//         .fragment = sc.editorGridFrag,
//         .bufUses = &.{
//             p.BufferUse.init(def.camBuf, .Mesh, .UniformRead, 0),
//         },
//         .colorAtts = &.{p.AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
//         .depthAtt = p.AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, null),
//         .renderState = .{
//             .colorBlend = .False,
//             .depthTest = .True,
//             .depthWrite = .True,
//             .depthCompare = .Greater,
//             .cullMode = .None,
//         },
//     });
// }

pub const editorGridGridDebugPass = p.PassDefinition.init(.{
    .name = "EditorGridGridDebug",
    .outputTex = "DebugGridOutputTex",
    .passAttributes = &.{
        p.PassAttrib.exec(.{
            .taskOrMesh = .{
                .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            },
        }),
        //
        p.PassAttrib.shader(sc.editorGridMesh),
        p.PassAttrib.shader(sc.editorGridFrag),
        //
        p.PassAttrib.color(.{ .in = "DebugGridOutputTex" }, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } }),
        p.PassAttrib.depth(.{ .in = "DebugGridDepthTex", .out = "DebugGridDepthOutputTex" }, .EarlyAndLateFragTest, .DepthStencilReadWrite, null),
        //
        p.PassAttrib.buf(.{ .in = "DebugCamUB" }, .Mesh, .UniformRead, 0),
        //
        p.PassAttrib.state(.{ .colorBlend = .False }),
        p.PassAttrib.state(.{ .depthTest = .True }),
        p.PassAttrib.state(.{ .depthWrite = .True }),
        p.PassAttrib.state(.{ .depthCompare = .Greater }),
        p.PassAttrib.state(.{ .cullMode = .None }),
    },
});

pub const editorGridPlaneDebugPass = p.PassDefinition.init(.{
    .name = "EditorGridPlaneDebug",

    .outputTex = "DebugPlaneOutputFrustumViewTex",
    .passAttributes = &.{
        p.PassAttrib.exec(.{
            .taskOrMesh = .{
                .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            },
        }),
        //
        p.PassAttrib.shader(sc.editorGridMesh),
        p.PassAttrib.shader(sc.editorGridFrag),
        //
        p.PassAttrib.color(.{ .in = "DebugPlaneOutputFrustumViewTex" }, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } }),
        p.PassAttrib.depth(.{ .in = "DebugPlaneDepthTex" }, .EarlyAndLateFragTest, .DepthStencilReadWrite, null),
        //
        p.PassAttrib.buf(.{ .in = "DebugCamUB" }, .Mesh, .UniformRead, 0),
        //
        p.PassAttrib.state(.{ .colorBlend = .False }),
        p.PassAttrib.state(.{ .depthTest = .True }),
        p.PassAttrib.state(.{ .depthWrite = .True }),
        p.PassAttrib.state(.{ .depthCompare = .Greater }),
        p.PassAttrib.state(.{ .cullMode = .None }),
    },
});
