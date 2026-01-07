const vk = @import("../modules/vk.zig").c;
const vkFn = @import("../modules/vk.zig");
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const PendingTransfer = @import("resources/ResourceManager.zig").PendingTransfer;
const vh = @import("Helpers.zig");

pub const GraphicState = struct {
    // Rasterization & Geometry
    polygonMode: u32 = vk.VK_POLYGON_MODE_FILL,
    cullMode: u32 = vk.VK_CULL_MODE_FRONT_BIT,
    frontFace: u32 = vk.VK_FRONT_FACE_CLOCKWISE,
    topology: u32 = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,

    primitiveRestart: u32 = vk.VK_FALSE,
    rasterDiscard: u32 = vk.VK_FALSE,
    rasterSamples: u32 = vk.VK_SAMPLE_COUNT_1_BIT,
    sample: struct { sampling: u32 = vk.VK_SAMPLE_COUNT_1_BIT, sampleMask: u32 = 0xFFFFFFFF } = .{},

    // Depth & Stencil
    depthTest: u32 = vk.VK_FALSE,
    depthWrite: u32 = vk.VK_FALSE,
    depthBoundsTest: u32 = vk.VK_FALSE,
    depthBias: u32 = vk.VK_FALSE,
    depthValues: struct { constant: f32 = 0.0, clamp: f32 = 0.0, slope: f32 = 0.0 } = .{},
    depthClamp: u32 = vk.VK_FALSE,
    depthStencilTest: u32 = vk.VK_FALSE,

    // // Color & Blending
    colorBlend: u32 = vk.VK_TRUE,
    colorBlendEquation: struct {
        srcColor: u32 = vk.VK_BLEND_FACTOR_SRC_ALPHA,
        dstColor: u32 = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        colorOperation: u32 = vk.VK_BLEND_OP_ADD,
        srcAlpha: u32 = vk.VK_BLEND_FACTOR_ONE,
        dstAlpha: u32 = vk.VK_BLEND_FACTOR_ZERO,
        alphaOperation: u32 = vk.VK_BLEND_OP_ADD,
    } = .{},

    colorWriteMask: u32 = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,

    blendConstants: struct { red: f32 = 0.0, green: f32 = 0.0, blue: f32 = 0.0, alpha: f32 = 0.0 } = .{},

    logicOp: u32 = vk.VK_FALSE,
    alphaToOne: u32 = vk.VK_FALSE,
    alphaToCoverage: u32 = vk.VK_FALSE,

    // // Advanced / Debug
    lineWidth: f32 = 2.0,
    conservativeRasterMode: u32 = vk.VK_CONSERVATIVE_RASTERIZATION_MODE_DISABLED_EXT,

    fragShadingRate: struct { width: u32 = 1, height: u32 = 1, operation: u32 = vk.VK_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_KHR } = .{},
};
