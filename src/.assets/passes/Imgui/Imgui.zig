const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

pub fn ImGuiPass(def: struct {
    string: []const u8,
    vertexBuf: p.BufId,
    indexBuf: p.BufId,
}) p.PassInstance {
    return p.PassInstance.Graphics(.{
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
        .vertexBuffers = &.{p.VertexBufferFill.init(def.vertexBuf, 0, 20, vk.VK_VERTEX_INPUT_RATE_VERTEX)},
        .indexBuffer = p.IndexBufferFill.init(def.indexBuf, vk.VK_INDEX_TYPE_UINT16),
        .vertexAttributes = &.{
            p.VertexAttribute{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 0 },
            p.VertexAttribute{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 8 },
            p.VertexAttribute{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = 16 },
        },
    });
}

pub const imguiPass = p.PassDefinition.init(.{
    .name = "Imgui",
    .outputTex = null, // Uses Swapchain
    .attributes = &.{
        p.PassAttrib.execGraphics(.{ .vertices = 0, .instances = 1, .indexCount = 0 }),
        //
        p.PassAttrib.shader(sc.imguiVert),
        p.PassAttrib.shader(sc.imguiFrag),
        //
        p.PassAttrib.vertexBuf("ImguiVB", 0, 20, vk.VK_VERTEX_INPUT_RATE_VERTEX),
        p.PassAttrib.indexBuf("ImguiIB", vk.VK_INDEX_TYPE_UINT16),
        //
        p.PassAttrib.vertexAttrib(0, 0, vk.VK_FORMAT_R32G32_SFLOAT, 0),
        p.PassAttrib.vertexAttrib(1, 0, vk.VK_FORMAT_R32G32_SFLOAT, 8),
        p.PassAttrib.vertexAttrib(2, 0, vk.VK_FORMAT_R8G8B8A8_UNORM, 16),
        //
        p.PassAttrib.state(.{ .cullMode = .None }),
        p.PassAttrib.state(.{ .depthTest = .False }),
        p.PassAttrib.state(.{ .depthWrite = .False }),
        p.PassAttrib.state(.{ .colorBlend = .True }),
        //
        p.PassAttrib.state(.{
            .colorBlendEquation = .{
                .srcColor = .SrcAlpha,
                .dstColor = .OneMinusSrcAlpha,
                .colorOperation = .Add,
                .srcAlpha = .One,
                .dstAlpha = .OneMinusSrcAlpha,
                .alphaOperation = .Add,
            },
        }),
    },
});
