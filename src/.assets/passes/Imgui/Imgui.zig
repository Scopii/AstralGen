const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

pub fn ImGuiPass(def: struct {
    name: p.PassEnum,
    vertexBuf: p.BufferEnum,
    indexBuf: p.BufferEnum,
}) p.PassDef {
    return p.PassDef.Graphics(.{
        .name = def.name,
        .outputTexId = null, // Uses Swapchain
        .execution = .{ .vertices = 0, .instances = 1, .indexCount = 0 },
        .vertex = sc.imguiVert,
        .fragment = sc.imguiFrag,
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
        .vertexBuffers = &.{p.VertexBufferUse.init(def.vertexBuf, 0, 20, vk.VK_VERTEX_INPUT_RATE_VERTEX)},
        .indexBuffer = p.IndexBufferUse.init(def.indexBuf, vk.VK_INDEX_TYPE_UINT16),
        .vertexAttributes = &.{
            p.VertexAttribute{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 0 },
            p.VertexAttribute{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 8 },
            p.VertexAttribute{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = 16 },
        },
    });
}