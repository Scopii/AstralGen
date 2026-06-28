const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

pub fn Composite(
    def: struct {
        string: []const u8,
    },
) p.PassInstance {
    return p.PassInstance.Graphics(.{
        .name = def.string,
        .outputTexId = null, // Uses Swapchain
        .execution = .{ .vertices = 3, .instances = 1, .indexCount = 0 },
        .vertex = sc.compositeVert,
        .fragment = sc.compositeFrag,
        .renderState = .{
            .colorBlend = .True,
            .colorBlendEquation = .{
                .srcColor = .SrcAlpha,
                .dstColor = .OneMinusSrcAlpha,
                .colorOperation = .Add,
                .srcAlpha = .One,
                .dstAlpha = .OneMinusSrcAlpha,
                .alphaOperation = .Add,
            },
            .depthTest = .False,
            .depthWrite = .False,
            .cullMode = .None,
        },
    });
}

// pub const compositePass = p.PassDefinition.init(.{
//     .name = "Composite",
//     .outputTex = null, // Uses Swapchain
//     .attributes = &.{
//         p.PassAttrib.execGraphics(.{ .vertices = 3, .instances = 1, .indexCount = 0 }),
//         //
//         p.PassAttrib.shader(sc.compositeVert),
//         p.PassAttrib.shader(sc.compositeFrag),
//         //
//         p.PassAttrib.state(.{ .colorBlend = .True }),
//         p.PassAttrib.state(.{ .depthTest = .False }),
//         p.PassAttrib.state(.{ .depthWrite = .False }),
//         p.PassAttrib.state(.{ .cullMode = .None }),

//         p.PassAttrib.state(.{
//             .colorBlendEquation = .{
//                 .srcColor = .SrcAlpha,
//                 .dstColor = .OneMinusSrcAlpha,
//                 .colorOperation = .Add,
//                 .srcAlpha = .One,
//                 .dstAlpha = .OneMinusSrcAlpha,
//                 .alphaOperation = .Add,
//             },
//         }),
//     },
// });
