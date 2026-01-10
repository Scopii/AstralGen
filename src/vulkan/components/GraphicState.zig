const vk = @import("../../modules/vk.zig").c;

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
    depthBoundsTest: u32 = vk.VK_FALSE,
    depthBias: u32 = vk.VK_FALSE,
    depthClamp: u32 = vk.VK_FALSE,
    depthTest: u32 = vk.VK_FALSE,
    depthWrite: u32 = vk.VK_FALSE,
    depthCompare: u32 = vk.VK_COMPARE_OP_LESS,
    depthValues: struct { constant: f32 = 0.0, clamp: f32 = 0.0, slope: f32 = 0.0 } = .{},

    stencilTest: u32 = vk.VK_FALSE,
    stencilOp: [5]u32 = .{ vk.VK_STENCIL_FACE_FRONT_AND_BACK, vk.VK_STENCIL_OP_KEEP, vk.VK_STENCIL_OP_KEEP, vk.VK_STENCIL_OP_KEEP, vk.VK_COMPARE_OP_ALWAYS },
    stencilCompare: struct { faceMask: u32 = vk.VK_STENCIL_FACE_FRONT_AND_BACK, mask: u32 = 0xFFFFFFFF } = .{},
    stencilWrite: struct { faceMask: u32 = vk.VK_STENCIL_FACE_FRONT_AND_BACK, mask: u32 = 0xFFFFFFFF } = .{},
    stencilReference: struct { faceMask: u32 = vk.VK_STENCIL_FACE_FRONT_AND_BACK, mask: u32 = 0 } = .{},

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

    blendConstants: struct { red: f32 = 0.0, green: f32 = 0.0, blue: f32 = 0.0, alpha: f32 = 0.0 } = .{},
    colorWriteMask: u32 = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,

    alphaToOne: u32 = vk.VK_FALSE,
    alphaToCoverage: u32 = vk.VK_FALSE,
    
    logicOp: u32 = vk.VK_FALSE,
    logicOpType: u32 = vk.VK_LOGIC_OP_COPY,

    // // Advanced / Debug
    lineWidth: f32 = 2.0,
    conservativeRasterMode: u32 = vk.VK_CONSERVATIVE_RASTERIZATION_MODE_DISABLED_EXT,

    fragShadingRate: struct { width: u32 = 1, height: u32 = 1, operation: u32 = vk.VK_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_KHR } = .{},
};
