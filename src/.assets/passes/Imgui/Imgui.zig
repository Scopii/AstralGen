const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

pub fn ImGuiPass(def: struct {
    string: []const u8,
    vertexBuf: p.BufferEnum,
    indexBuf: p.BufferEnum,
}) p.PassDef {
    return p.PassDef.Graphics(.{
        .name = def.string,
        .outputTexId = null, // Uses Swapchain
        .execution = .{ .vertices = 0, .instances = 1, .indexCount = 0 },
        .vertex = sc.imguiVert,
        .fragment = sc.imguiFrag,
        .renderState = .{
            .cullMode = .None,
            .depthTest = .False,
            .depthWrite = .False,
            .colorBlend = .True,
            .colorBlendEquation = .{
                .srcColor = .SrcAlpha,
                .dstColor = .OneMinusSrcAlpha,
                .colorOperation = .Add,
                .srcAlpha = .One,
                .dstAlpha = .OneMinusSrcAlpha,
                .alphaOperation = .Add,
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
