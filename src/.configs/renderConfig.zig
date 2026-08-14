const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const ClearColor = @import("../render/types/pass/AttachmentUse.zig").ClearColor;
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

pub const FRAME_LIMIT = 15000;

// Additional Debug Prints
pub const BARRIER_DEBUG = false;
pub const RESOURCE_DEBUG = true;
pub const DESCRIPTOR_DEBUG = true;
pub const COMPOSITE_DEBUG = false;

// Frame Graph and Pass System
pub const PASS_MAX = 128;
pub const MAX_PASS_ATTRIBUTES = 80;
pub const PASS_EXTRACTION_DEBUG = false;

pub const FRAME_GRAPH_DEBUG = true;
pub const FRAME_GRAPH_TIMERS = false;
pub const FRAME_GRAPH_SORT_DEBUG = false;

pub const FRAME_GRAPH_SKIP_OPTIMIZE = false;
pub const FRAME_GRAPH_SKIP_SHARING = false;
pub const FRAME_GRAPH_AGGRESSIVE_TEXTURE_SHARE = true;

pub const PASS_TEXTURE_RESIZE_INCLUDES_READ = true;
pub const FRAME_BUILDS_TILL_TRANSIENT_DELETION = 0;

pub const RENDER_COMPILER_DEBUG = false;

// Rendering, Swapchains and Windows
pub const EARLY_GPU_WAIT = true; // (Reflex Mode)
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = vk.VK_PRESENT_MODE_IMMEDIATE_KHR; //vk.VK_PRESENT_MODE_IMMEDIATE_KHR
pub const MAX_WINDOWS: u8 = 8;
pub const COMPOSITE_TEX_STRETCH = false;
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
pub const INDIRECT_SB = BufDesc{ .share = .transient, .mem = .Gpu, .typ = .Indirect, .len = 1, .elementSize = @sizeOf(vhT.IndirectData), .update = .PerFrame };
pub const READBACK_SB = BufDesc{ .share = .persistent, .mem = .CpuRead, .typ = .Storage, .len = 1, .elementSize = @sizeOf(vhT.ReadbackData), .update = .PerFrame };

pub const ENTITY_SB = BufDesc{ .share = .persistent, .mem = .Gpu, .typ = .Storage, .len = ENTITY_COUNT, .elementSize = @sizeOf(GpuObjectData), .update = .Rarely, .resize = .Fit };
pub const CAMERA_UB = BufDesc{ .share = .persistent, .mem = .Gpu, .typ = .Uniform, .len = 1, .elementSize = @sizeOf(CameraData), .update = .Often, .resize = .Fit };

pub const IMGUI_VB = BufDesc{ .share = .persistent, .mem = .Gpu, .typ = .Vertex, .len = 1024 * 1024, .elementSize = 1, .update = .Often, .resize = .Grow };
pub const IMGUI_IB = BufDesc{ .share = .persistent, .mem = .Gpu, .typ = .Index, .len = 1024 * 1024, .elementSize = 1, .update = .Often, .resize = .Grow };

// Textures
pub const TRANSIENT_COLOR_TEX = TexDesc{
    .share = .transient,
    .mem = .Gpu,
    .descriptors = .StorageSampled, // Should be inferred
    .texUse = .{ .storage = true, .colorAtt = true, .sampled = true }, // Should be inferred
    .typ = .Color16,
    .width = 16,
    .height = 9,
    .update = .Rarely,
    .resize = .Block,
    .fitPass = true,
};

pub const TRANSIENT_DEPTH_TEX = TexDesc{
    .share = .transient, // WAS PERSISTENT
    .mem = .Gpu,
    .texUse = .{ .depthAtt = true, .sampled = true, .transferSrc = false },
    .descriptors = .SampledOnly,
    .typ = .Depth32,
    .width = 16,
    .height = 9,
    .update = .Rarely,
    .resize = .Block,
    .fitPass = true,
};

pub const PERSISTENT_COLOR_TEX = TexDesc{
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

pub const IMGUI_FONT_TEX = TexDesc{
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
