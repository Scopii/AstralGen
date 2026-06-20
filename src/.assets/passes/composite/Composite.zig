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
            .colorBlend = vk.VK_TRUE,
            .colorBlendEquation = .{
                .srcColor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
                .dstColor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
                .srcAlpha = vk.VK_BLEND_FACTOR_ONE,
                .dstAlpha = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            },
            .depthTest = vk.VK_FALSE,
            .depthWrite = vk.VK_FALSE,
            .cullMode = vk.VK_CULL_MODE_NONE,
        },
    });
}
