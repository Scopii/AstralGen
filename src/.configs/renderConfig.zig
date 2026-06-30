const ClearColor = @import("../render/types/pass/AttachmentSlot.zig").AttachmentSlot.ClearColor;
const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const CameraData = @import("../camera/CameraSys.zig").CamData;
const vhT = @import("../render/help/Types.zig");
const vk = @import("../.modules/vk.zig").c;

const GpuObjectData = @import("../render/help/Types.zig").GpuObjectData;

pub const ENTITY_COUNT = 30;
pub const ENTITY_MAX = 512;

// Vulkan Validation Layers
pub const VALIDATION = true;
pub const GPU_VALIDATION = false;
pub const BEST_PRACTICES = false;
pub const ROBUST_VALIDATION = false;

// Normal Profiling
pub const GPU_TIMERS = true;
pub const GPU_STATS = false;

pub const GPU_QUERY_INTERVAL = 1;
pub const GPU_TIME_QUERYS = 63;
pub const GPU_STATS_QUERYS: u8 = 32;
pub const STATS_MASK: vk.VkQueryPipelineStatisticFlagBits =
    // vk.VK_QUERY_PIPELINE_STATISTIC_CLIPPING_INVOCATIONS_BIT |
    // vk.VK_QUERY_PIPELINE_STATISTIC_CLIPPING_PRIMITIVES_BIT |
    vk.VK_QUERY_PIPELINE_STATISTIC_COMPUTE_SHADER_INVOCATIONS_BIT |
    vk.VK_QUERY_PIPELINE_STATISTIC_FRAGMENT_SHADER_INVOCATIONS_BIT;
// vk.VK_QUERY_PIPELINE_STATISTIC_TASK_SHADER_INVOCATIONS_BIT_EXT |
// vk.VK_QUERY_PIPELINE_STATISTIC_MESH_SHADER_INVOCATIONS_BIT_EXT;

pub const GPU_READBACK = false;
pub const CPU_PROFILING = false;
pub const SWAPCHAIN_PROFILING = false;

// Additional Debug Prints
pub const BARRIER_DEBUG = false;
pub const RESOURCE_DEBUG = true;
pub const DESCRIPTOR_DEBUG = true;
pub const PASS_EXTRACTION_DEBUG = false;
pub const FRAME_GRAPH_DEBUG = true;
pub const FRAME_BUILDS_TILL_TRANSIENT_DELETION = 0;
pub const PASS_MAX = 128;
pub const MAX_PASS_ATTRIBUTES = 80;

// Rendering, Swapchains and Windows
pub const EARLY_GPU_WAIT = true; // (Reflex Mode)
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = vk.VK_PRESENT_MODE_IMMEDIATE_KHR; //vk.VK_PRESENT_MODE_IMMEDIATE_KHR
pub const MAX_WINDOWS: u8 = 8;
pub const LINKED_TEX_MAX = 12;
pub const RENDER_TEX_AUTO_RESIZE = true;
pub const RENDER_TEX_STRETCH = true; // Maybe ignored on AUTO_RESIZE
pub const USE_MEM_BARRIERS_ON_BUFFERS = true;
pub const USE_MEM_BARRIER_ON_IMAGES = true;
pub const INITIAL_SWAPCHAIN_COLOR: ClearColor = .{ .R = 0.0, .G = 0.0, .B = 0.1, .A = 1.0 };

// Resource Information
pub const BUF_MAX = 63;
pub const STORAGE_TEX_MAX = 31;
pub const SAMPLED_TEX_MAX = 31;
pub const TEX_MAX = STORAGE_TEX_MAX + SAMPLED_TEX_MAX;
pub const RESOURCE_MAX = TEX_MAX + BUF_MAX;
pub const STAGING_BUF_SIZE = 32 * 1024 * 1024; // Bytes
pub const SAMPLER_LINEAR_CLAMP_INDEX: u31 = 0;
pub const SAMPLER_NEAREST_CLAMP_INDEX: u31 = 1;
pub const SAMPLER_MAX: u32 = 2;

//////////////// RESOURCE DESCRIPTIONS ///////////////

// Buffers
pub const indirectSBDesc = BufDesc{ .share = .persistent, .mem = .Gpu, .typ = .Indirect, .len = 1, .elementSize = @sizeOf(vhT.IndirectData), .update = .PerFrame };
pub const readbackSBDesc = BufDesc{ .share = .persistent, .mem = .CpuRead, .typ = .Storage, .len = 1, .elementSize = @sizeOf(vhT.ReadbackData), .update = .PerFrame };

pub const entitySBDesc = BufDesc{ .share = .persistent, .mem = .Gpu, .typ = .Storage, .len = ENTITY_COUNT, .elementSize = @sizeOf(GpuObjectData), .update = .Rarely, .resize = .Fit };
pub const mainCamUBDesc = BufDesc{ .share = .persistent, .mem = .Gpu, .typ = .Uniform, .len = 1, .elementSize = @sizeOf(CameraData), .update = .Often, .resize = .Fit };
pub const debugCamUBDesc = BufDesc{ .share = .persistent, .mem = .Gpu, .typ = .Uniform, .len = 1, .elementSize = @sizeOf(CameraData), .update = .Often, .resize = .Fit };

pub const imguiVBDesc = BufDesc{ .share = .persistent, .mem = .Gpu, .typ = .Vertex, .len = 1024 * 1024, .elementSize = 1, .update = .Often, .resize = .Grow };
pub const imguiIBDesc = BufDesc{ .share = .persistent, .mem = .Gpu, .typ = .Index, .len = 1024 * 1024, .elementSize = 1, .update = .Often, .resize = .Grow };

// Textures
pub const rayMarchTexDesc = TexDesc{
    .share = .transient, // transient
    .mem = .Gpu,
    .descriptors = .StorageSampled,
    .texUse = .{ .storage = true, .colorAtt = true, .sampled = true },
    .typ = .Color16,
    .width = 1920,
    .height = 1080,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = true,
};

pub const gridTexDesc = TexDesc{
    .share = .transient, // transient
    .mem = .Gpu,
    .descriptors = .StorageSampled,
    .texUse = .{ .storage = true, .colorAtt = true, .sampled = true },
    .typ = .Color16,
    .width = 1920,
    .height = 1080,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = true,
};

pub const gridDepthTexDesc = TexDesc{
    .share = .persistent,
    .mem = .Gpu,
    .texUse = .{ .depthAtt = true, .sampled = true, .transferSrc = false },
    .descriptors = .SampledOnly,
    .typ = .Depth32,
    .width = 1920,
    .height = 1080,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = true,
};

pub const planeTexDesc = TexDesc{
    .share = .transient, // transient
    .mem = .Gpu,
    .descriptors = .StorageSampled,
    .texUse = .{ .storage = true, .colorAtt = true, .sampled = true },
    .typ = .Color16,
    .width = 1920,
    .height = 1080,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = true,
};

pub const planeDepthTexDesc = TexDesc{
    .share = .persistent,
    .mem = .Gpu,
    .texUse = .{ .depthAtt = true, .sampled = true, .transferSrc = false },
    .descriptors = .SampledOnly,
    .typ = .Depth32,
    .width = 1920,
    .height = 1080,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = true,
};

pub const debugGridTexDesc = TexDesc{
    .share = .transient, // transient
    .mem = .Gpu,
    .descriptors = .StorageSampled,
    .texUse = .{ .storage = true, .colorAtt = true, .sampled = true },
    .typ = .Color16,
    .width = 1920,
    .height = 1080,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = true,
};

pub const debugPlaneTexDesc = TexDesc{
    .share = .transient, // transient
    .mem = .Gpu,
    .descriptors = .StorageSampled,
    .texUse = .{ .storage = true, .colorAtt = true, .sampled = true },
    .typ = .Color16,
    .width = 1920,
    .height = 1080,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = true,
};

pub const debugGridDepthTexDesc = TexDesc{
    .share = .transient, // Transient??
    .mem = .Gpu,
    .texUse = .{ .depthAtt = true, .sampled = true, .transferSrc = false },
    .descriptors = .SampledOnly,
    .typ = .Depth32,
    .width = 1920,
    .height = 1080,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = true,
};

pub const debugPlaneDepthTexDesc = TexDesc{
    .share = .transient, // Transient??
    .mem = .Gpu,
    .texUse = .{ .depthAtt = true, .sampled = true, .transferSrc = false },
    .descriptors = .SampledOnly,
    .typ = .Depth32,
    .width = 1920,
    .height = 1080,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = true,
};

pub const testTilesTexDesc = TexDesc{
    .share = .persistent,
    .mem = .Gpu,
    .texUse = .{ .storage = true, .colorAtt = true },
    .descriptors = .StorageOnly,
    .typ = .Color16,
    .width = 256,
    .height = 256,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = false,
};

pub const imguiFontTexDesc = TexDesc{
    .share = .persistent,
    .mem = .Gpu,
    .texUse = .{ .colorAtt = true, .sampled = true },
    .typ = .Color8,
    .descriptors = .SampledOnly,
    .width = 1,
    .height = 1,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = false,
};

pub const depthViewTexDesc = TexDesc{
    .share = .transient,
    .mem = .Gpu,
    .texUse = .{ .storage = true, .colorAtt = true, .sampled = true },
    .descriptors = .StorageSampled,
    .typ = .Color16,
    .width = 1920,
    .height = 1080,
    .update = .Rarely,
    .resize = .Fit,
    .fitPass = true,
};

pub const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
pub const QuantIndirectInputSB: BufPassId = .id(1);
pub const QuantIndirectOutputSB: BufPassId = .id(2);
pub const ReadbackSB: BufPassId = .id(3);
pub const EntitySB: BufPassId = .id(4);
pub const MainCamUB: BufPassId = .id(5);
pub const DebugCamUB: BufPassId = .id(6);
pub const ImguiVB: BufPassId = .id(7);
pub const ImguiIB: BufPassId = .id(8);

pub const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
pub const RayMarchInputTex: TexPassId = .id(1);
pub const GridTex: TexPassId = .id(2);
pub const GridDepthTex: TexPassId = .id(3);
pub const DebugGridInputTex: TexPassId = .id(4);
pub const DebugGridOutputTex: TexPassId = .id(5);
pub const DebugGridDepthTex: TexPassId = .id(6);
pub const DebugGridDepthOutputTex: TexPassId = .id(7);
pub const PlaneTex: TexPassId = .id(8);
pub const PlaneDepthTex: TexPassId = .id(9);
pub const DebugPlaneInputTex: TexPassId = .id(10);
pub const DebugPlaneOutputTex: TexPassId = .id(11);
pub const DebugPlaneOutputFrustumViewTex: TexPassId = .id(12);
pub const DebugPlaneDepthTex: TexPassId = .id(13);
pub const DepthViewTex: TexPassId = .id(14);
pub const TestTileTex: TexPassId = .id(15);
pub const ImguiFontTex: TexPassId = .id(16);
// pub const Swapchain: TexPassId = .id(17);
