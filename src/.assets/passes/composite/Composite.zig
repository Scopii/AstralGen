const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

pub fn Composite(
    def: struct {
        string: []const u8,
    },
) p.PassDef {
    return p.PassDef.Graphics(.{
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
