const vk = @import("../modules/vk.zig").c;
const Object = @import("../ecs/EntityManager.zig").Object;
const sc = @import("shaderConfig.zig");

// Rendering, Swapchains and Windows
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = vk.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const MAX_WINDOWS: u8 = 16;

pub const GPU_IMG_MAX = 64;
pub const GPU_BUF_MAX = 16;
pub const RENDER_IMG_FORMAT = vk.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const RENDER_IMG_AUTO_RESIZE = true;
pub const RENDER_IMG_STRETCH = true; // Ignored on AUTO_RESIZE

pub const RenderType = enum { computePass, graphicsPass, meshPass, taskMeshPass, vertexPass };

pub const GpuBufferInfo = struct {
    pub const BufferUsage = enum(vk.VkBufferUsageFlags) {
        Storage, // STORAGE_BUFFER
        Uniform, // UNIFORM_BUFFER
        Index, // INDEX_BUFFER
        Vertex, // VERTEX_BUFFER
        Staging, // TRANSFER_SRC
    };
    pub const MemoryUsage = enum {
        GpuOptimal, // Fastest (needs Staging Buffer Updates)
        CpuWriteOptimal, // Slower (CPU writes, GPU reads)
        CpuReadOptimal, // Very Slow (GPU writes, CPU reads)
    };

    buffId: u8,
    length: u64,
    dataType: type,
    memUsage: MemoryUsage,
    buffUsage: BufferUsage,
};

pub const gpuBuf1: GpuBufferInfo = .{ .buffId = 0, .length = 1000, .dataType = Object, .memUsage = .CpuWriteOptimal, .buffUsage = .Storage };
pub const gpuBufInfos: []const GpuBufferInfo = &.{gpuBuf1};

pub const GpuImageInfo = struct {
    id: u8,
    extent: vk.VkExtent3D,
    imgFormat: c_uint = RENDER_IMG_FORMAT,
    memUsage: c_uint = vk.VMA_MEMORY_USAGE_GPU_ONLY,
};

pub const passInfo = struct {
    renderImg: GpuImageInfo,
    shaderIds: []const u8,
    clear: bool = false,
};

// Render
pub const renderImg1 = GpuImageInfo{ .id = 0, .extent = .{ .width = 500, .height = 500, .depth = 1 } };
pub const pass1: passInfo = .{ .renderImg = renderImg1, .shaderIds = &.{sc.t1Comp.id} }; // clear does not work for compute

pub const renderImg2 = GpuImageInfo{ .id = 1, .extent = .{ .width = 300, .height = 300, .depth = 1 } };
pub const pass2: passInfo = .{ .renderImg = renderImg2, .shaderIds = &.{ sc.t2Vert.id, sc.t2Frag.id } };

pub const renderImg3 = GpuImageInfo{ .id = 15, .extent = .{ .width = 100, .height = 100, .depth = 1 } };
pub const pass3: passInfo = .{ .renderImg = renderImg3, .shaderIds = &.{ sc.t3Mesh.id, sc.t3Frag.id } };

pub const renderImg4 = GpuImageInfo{ .id = 7, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } };
pub const pass4: passInfo = .{ .renderImg = renderImg4, .shaderIds = &.{ sc.t4Task.id, sc.t4Mesh.id, sc.t4Frag.id } };

pub const renderImg5 = GpuImageInfo{ .id = 7, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } };
pub const pass5: passInfo = .{ .renderImg = renderImg4, .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id }, .clear = true };

pub const renderSeq2: []const passInfo = &.{ pass1, pass2, pass3, pass4, pass5 };
