const vk = @import("../../../.modules/vk.zig").c;

pub const PolygonMode = enum(vk.VkPolygonMode) { Fill = vk.VK_POLYGON_MODE_FILL };
pub const CullMode = enum(vk.VkCullModeFlags) {
    Front = vk.VK_CULL_MODE_FRONT_BIT,
    None = vk.VK_CULL_MODE_NONE,
    Back = vk.VK_CULL_MODE_BACK_BIT,
};
pub const FrontFace = enum(vk.VkFrontFace) { Clockwise = vk.VK_FRONT_FACE_CLOCKWISE, CounterClockwise = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE };
pub const Topology = enum(vk.VkPrimitiveTopology) { TriangleList = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };

pub const PrimitiveRestart = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };
pub const RasterDiscard = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };
pub const RasterSamples = enum(vk.VkSampleCountFlagBits) { OneBit = vk.VK_SAMPLE_COUNT_1_BIT };

pub const Sample = struct {
    sampling: enum(vk.VkSampleCountFlagBits) { OneBit = vk.VK_SAMPLE_COUNT_1_BIT },
    sampleMask: enum(vk.VkSampleMask) { White = 0xFFFFFFFF },
};

pub const DepthBoundsTest = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };
pub const DepthBias = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };
pub const DepthClamp = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };
pub const DepthTest = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };
pub const DepthWrite = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };
pub const DepthCompare = enum(vk.VkCompareOp) { Greater = vk.VK_COMPARE_OP_GREATER, Less = vk.VK_COMPARE_OP_LESS };
pub const DepthValues = struct { constant: f32 = 0.0, clamp: f32 = 0.0, slope: f32 = 0.0 };

pub const StencilTest = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };
pub const StencilOp = struct {
    faceMask: enum(vk.VkStencilFaceFlags) { FaceFrontAndBack = vk.VK_STENCIL_FACE_FRONT_AND_BACK },
    failOp: enum(vk.VkStencilOp) { Keep = vk.VK_STENCIL_OP_KEEP },
    passOp: enum(vk.VkStencilOp) { Keep = vk.VK_STENCIL_OP_KEEP },
    depthFailOp: enum(vk.VkStencilOp) { Keep = vk.VK_STENCIL_OP_KEEP },
    compareOp: enum(vk.VkCompareOp) { Always = vk.VK_COMPARE_OP_ALWAYS },
};
pub const StencilCompare = struct {
    faceMask: enum(vk.VkStencilFaceFlags) { FaceFrontAndBack = vk.VK_STENCIL_FACE_FRONT_AND_BACK },
    mask: u32,
};
pub const StencilWrite = struct {
    faceMask: enum(vk.VkStencilFaceFlags) { FaceFrontAndBack = vk.VK_STENCIL_FACE_FRONT_AND_BACK },
    mask: u32,
};
pub const StencilReference = struct {
    faceMask: enum(vk.VkStencilFaceFlags) { FaceFrontAndBack = vk.VK_STENCIL_FACE_FRONT_AND_BACK },
    mask: u32,
};

pub const ColorBlend = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };

pub const ColorBlendEquation = struct {
    srcColor: BlendFactor,
    dstColor: BlendFactor,
    colorOperation: enum(vk.VkBlendOp) { Add = vk.VK_BLEND_OP_ADD },
    srcAlpha: BlendFactor,
    dstAlpha: BlendFactor,
    alphaOperation: enum(vk.VkBlendOp) { Add = vk.VK_BLEND_OP_ADD },

    pub const BlendFactor = enum(vk.VkBlendFactor) {
        SrcAlpha = vk.VK_BLEND_FACTOR_SRC_ALPHA,
        OneMinusSrcAlpha = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        One = vk.VK_BLEND_FACTOR_ONE,
        Zero = vk.VK_BLEND_FACTOR_ZERO,
    };
};

pub const BlendConstants = struct { red: f32 = 0.0, green: f32 = 0.0, blue: f32 = 0.0, alpha: f32 = 0.0 };

pub const ColorWriteMask = enum(vk.VkColorComponentFlags) { RGBA = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT };

pub const AlphaToOne = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };
pub const AlphaToCoverage = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };
pub const LogicOp = enum(vk.VkBool32) { False = vk.VK_FALSE, True = vk.VK_TRUE };
pub const LogicOpType = enum(vk.VkLogicOp) { Copy = vk.VK_LOGIC_OP_COPY };

pub const ConservativeRasterMode = enum(vk.VkConservativeRasterizationModeEXT) { ConservativeRasterDisabled = vk.VK_CONSERVATIVE_RASTERIZATION_MODE_DISABLED_EXT };

pub const FragShadingRate = struct {
    width: u32 = 1,
    height: u32 = 1,
    operation1: enum(vk.VkFragmentShadingRateCombinerOpKHR) { Keep = vk.VK_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_KHR },
    operation2: enum(vk.VkFragmentShadingRateCombinerOpKHR) { Keep = vk.VK_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_KHR },
};

pub const RenderState = struct {
    // Rasterization & Geometry
    polygonMode: PolygonMode = .Fill,
    cullMode: CullMode = .Front,
    frontFace: FrontFace = .Clockwise,
    topology: Topology = .TriangleList,

    primitiveRestart: PrimitiveRestart = .False,
    rasterDiscard: RasterDiscard = .False,
    rasterSamples: RasterSamples = .OneBit,

    sample: Sample = .{ .sampling = .OneBit, .sampleMask = .White },

    // Depth & Stencil
    depthBoundsTest: DepthBoundsTest = .False,
    depthBias: DepthBias = .False,
    depthClamp: DepthClamp = .False,
    depthTest: DepthTest = .False,
    depthWrite: DepthWrite = .False,
    depthCompare: DepthCompare = .Greater, // LESS, for normal Z
    depthValues: DepthValues = .{},

    stencilTest: StencilTest = .False,
    stencilOp: StencilOp = .{ .faceMask = .FaceFrontAndBack, .failOp = .Keep, .passOp = .Keep, .depthFailOp = .Keep, .compareOp = .Always },
    stencilCompare: StencilCompare = .{ .faceMask = .FaceFrontAndBack, .mask = 0xFFFFFFFF },
    stencilWrite: StencilWrite = .{ .faceMask = .FaceFrontAndBack, .mask = 0xFFFFFFFF },
    stencilReference: StencilReference = .{ .faceMask = .FaceFrontAndBack, .mask = 0 },

    // // Color & Blending
    colorBlend: ColorBlend = .True,

    colorBlendEquation: ColorBlendEquation = .{
        .srcColor = .SrcAlpha,
        .dstColor = .OneMinusSrcAlpha,
        .colorOperation = .Add,
        .srcAlpha = .One,
        .dstAlpha = .Zero,
        .alphaOperation = .Add,
    },

    blendConstants: BlendConstants = .{},
    colorWriteMask: ColorWriteMask = .RGBA,

    alphaToOne: AlphaToOne = .False,
    alphaToCoverage: AlphaToCoverage = .False,

    logicOp: LogicOp = .False,
    logicOpType: LogicOpType = .Copy,

    // // Advanced / Debug
    lineWidth: f32 = 2.0,
    conservativeRasterMode: ConservativeRasterMode = .ConservativeRasterDisabled,

    fragShadingRate: FragShadingRate = .{ .width = 1, .height = 1, .operation1 = .Keep, .operation2 = .Keep },
};
