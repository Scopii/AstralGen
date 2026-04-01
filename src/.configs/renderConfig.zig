const Attachment = @import("../render/types/base/Pass.zig").Attachment;
const TextureUse = @import("../render/types/base/Pass.zig").TextureUse;
const BufferUse = @import("../render/types/base/Pass.zig").BufferUse;
const TextureMeta = @import("../render/types/res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../render/types/res/BufferMeta.zig").BufferMeta;
const CameraData = @import("../camera/CameraSys.zig").CamData;
const Pass = @import("../render/types/base/Pass.zig").Pass;
const vhT = @import("../render/help/Types.zig");
const vk = @import("../.modules/vk.zig").c;
const sc = @import("shaderConfig.zig");
const pDef = @import("passConfig.zig");

const GpuObjectData = @import("../render/help/Types.zig").GpuObjectData;

pub const ENTITY_COUNT = 30;
pub const ENTITY_MAX = 512;

// Vulkan Validation Layers
pub const VALIDATION = true;
pub const GPU_VALIDATION = false;
pub const BEST_PRACTICES = false;
pub const ROBUST_VALIDATION = false;

// Normal Profiling
pub const GPU_PROFILING = false;
pub const GPU_QUERY_INTERVAL = 100;

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

// Rendering, Swapchains and Windows
pub const EARLY_GPU_WAIT = true; // (Reflex Mode)
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = vk.VK_PRESENT_MODE_IMMEDIATE_KHR; //vk.VK_PRESENT_MODE_IMMEDIATE_KHR
pub const MAX_WINDOWS: u8 = 8;
pub const LINKED_TEX_MAX = 3;
pub const RENDER_TEX_AUTO_RESIZE = true;
pub const RENDER_TEX_STRETCH = true; // Ignored on AUTO_RESIZE

// Resource Information
pub const BUF_MAX = 63;
pub const STORAGE_TEX_MAX = 31;
pub const SAMPLED_TEX_MAX = 31;
pub const TEX_MAX = STORAGE_TEX_MAX + SAMPLED_TEX_MAX;
pub const RESOURCE_MAX = TEX_MAX + BUF_MAX;
pub const STAGING_BUF_SIZE = 32 * 1024 * 1024; // Bytes

pub const TEX_COLOR_FORMAT = vk.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const TEX_DEPTH_FORMAT = vk.VK_FORMAT_D32_SFLOAT;

// Buffers
pub const indirectSB = BufferMeta.create(.{ .id = .{ .val = 1 }, .mem = .Gpu, .typ = .Indirect, .len = 1, .elementSize = @sizeOf(vhT.IndirectData), .update = .PerFrame });
pub const readbackSB = BufferMeta.create(.{ .id = .{ .val = 2 }, .mem = .CpuRead, .typ = .Storage, .len = 1, .elementSize = @sizeOf(vhT.ReadbackData), .update = .PerFrame });

pub const entitySB = BufferMeta.create(.{ .id = .{ .val = 3 }, .mem = .Gpu, .typ = .Storage, .len = ENTITY_COUNT, .elementSize = @sizeOf(GpuObjectData), .update = .Rarely, .resize = .Fit });
pub const mainCamUB = BufferMeta.create(.{ .id = .{ .val = 4 }, .mem = .Gpu, .typ = .Uniform, .len = 1, .elementSize = @sizeOf(CameraData), .update = .Often, .resize = .Fit });
pub const debugCamUB = BufferMeta.create(.{ .id = .{ .val = 5 }, .mem = .Gpu, .typ = .Uniform, .len = 1, .elementSize = @sizeOf(CameraData), .update = .Often, .resize = .Fit });
pub const BUFFERS: []const BufferMeta.BufInf = &.{ entitySB, mainCamUB, debugCamUB, indirectSB, readbackSB };

// Textures
pub const rayTex = TextureMeta.create(.{ .id = .{ .val = 5 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1080, .update = .Rarely });

pub const mainTex = TextureMeta.create(.{ .id = .{ .val = 1 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1080, .update = .Rarely });
pub const mainDepthTex = TextureMeta.create(.{ .id = .{ .val = 2 }, .mem = .Gpu, .typ = .Depth, .width = 1920, .height = 1080, .update = .Rarely });

pub const debugTex = TextureMeta.create(.{ .id = .{ .val = 3 }, .mem = .Gpu, .typ = .Color, .width = 1920, .height = 1080, .update = .Rarely });
pub const debugDepthTex = TextureMeta.create(.{ .id = .{ .val = 4 }, .mem = .Gpu, .typ = .Depth, .width = 1920, .height = 1080, .update = .Rarely });
pub const TEXTURES: []const TextureMeta.TexInf = &.{ mainTex, mainDepthTex, debugTex, debugDepthTex, rayTex };

// Passes
pub const PASSES: []const Pass = &.{
    pDef.CompRayMarch(.{
        .name = "CompTest",
        .entityBuf = entitySB.id,
        .rayTex = rayTex.id,
        .camBuf = mainCamUB.id,
        .readbackBuf = readbackSB.id,
    }),

    Pass.init(.{ .name = "Blit to Viewport 1", .execution = .{ .viewportBlit = .{ .val = 1 } }, .shaderIds = &.{} }),

    pDef.CullComp(.{
        .name = "Cull-Comp",
        .indirectBuf = indirectSB.id,
        .entityBuf = entitySB.id,
    }),

    pDef.Cull(.{
        .name = "Cull-Main",
        .mainTex = mainTex.id,
        .mainDepthTex = mainDepthTex.id,
        .indirectBuf = indirectSB.id,
        .viewCam = mainCamUB.id,
        .cullCam = mainCamUB.id,
    }),

    pDef.Cull(.{
        .name = "Cull-Debug",
        .mainTex = debugTex.id,
        .mainDepthTex = debugDepthTex.id,
        .indirectBuf = indirectSB.id,
        .viewCam = debugCamUB.id,
        .cullCam = mainCamUB.id,
    }),

    pDef.FrustumView(.{
        .name = "FrustumView",
        .debugTex = debugTex.id,
        .debugDepthTex = debugDepthTex.id,
        .frustumCamBuf = mainCamUB.id,
        .viewCamBuf = debugCamUB.id,
    }),

    pDef.EditorGrid(.{
        .name = "Editor-Grid",
        .debugTex = debugTex.id,
        .debugDepthTex = debugDepthTex.id,
        .camBuf = debugCamUB.id,
    }),

    Pass.init(.{ .name = "Blit to Viewport 2", .execution = .{ .viewportBlit = .{ .val = 2 } }, .shaderIds = &.{} }),
    Pass.init(.{ .name = "Blit to Viewport 3", .execution = .{ .viewportBlit = .{ .val = 3 } }, .shaderIds = &.{} }),

    pDef.QuantComp(.{
        .name = "Quant-Comp",
        .indirectBuf = indirectSB.id,
        .entityBuf = entitySB.id,
    }),

    pDef.Quant(.{
        .name = "Quant-Main",
        .debugTex = mainTex.id,
        .debugDepthTex = mainDepthTex.id,
        .indirectBuf = indirectSB.id,
        .viewCam = mainCamUB.id,
        .cullCam = mainCamUB.id,
    }),

    pDef.Quant(.{
        .name = "Quant-Debug",
        .debugTex = debugTex.id,
        .debugDepthTex = debugDepthTex.id,
        .indirectBuf = indirectSB.id,
        .viewCam = debugCamUB.id,
        .cullCam = mainCamUB.id,
    }),

    // pDef.FrustumView(.{
    //     .name = "FrustumView",
    //     .debugTex = debugTex.id,
    //     .debugDepthTex = debugDepthTex.id,
    //     .frustumCamBuf = mainCamUB.id,
    //     .viewCamBuf = debugCamUB.id,
    // }),

    pDef.EditorGrid(.{
        .name = "Editor-Grid",
        .debugTex = debugTex.id,
        .debugDepthTex = debugDepthTex.id,
        .camBuf = debugCamUB.id,
    }),

    Pass.init(.{ .name = "Blit to Viewport 4", .execution = .{ .viewportBlit = .{ .val = 4 } }, .shaderIds = &.{} }),
    Pass.init(.{ .name = "Blit to Viewport 5", .execution = .{ .viewportBlit = .{ .val = 5 } }, .shaderIds = &.{} }),
};
