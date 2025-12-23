const vk = @import("../modules/vk.zig").c;
const Object = @import("../ecs/EntityManager.zig").Object;
const sc = @import("shaderConfig.zig");
const ShaderStage = @import("../vulkan/ShaderObject.zig").ShaderStage;

// Rendering, Swapchains and Windows
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = vk.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const MAX_WINDOWS: u8 = 16;

pub const GPU_BUF_MAX = 16;
pub const GPU_IMG_MAX = 64;
pub const GPU_RESOURCE_MAX = GPU_BUF_MAX + GPU_IMG_MAX;

pub const RENDER_IMG_BINDING = 0; // FOR UPDATING THE RENDER IMAGE ON WINDOW RESIZES
pub const RENDER_IMG_FORMAT = vk.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const RENDER_IMG_AUTO_RESIZE = true;
pub const RENDER_IMG_STRETCH = true; // Ignored on AUTO_RESIZE

pub const Pass = struct {
    pub const PassType = enum {
        computePass,
        graphicsPass,
        meshPass,
        taskMeshPass,
        vertexPass,
        empty,
    };
    passType: PassType = .empty,
    passImgId: u32,
    shaderIds: []const u8,
    clear: bool = false,
};

pub const ResourceState = struct { layout: vk.VkImageLayout, access: vk.VkAccessFlags, stage: vk.VkPipelineStageFlags }; // PREPARED FOR RENDER GRAPH

pub const ResourceInfo = struct {
    gpuId: u32,
    binding: u8,
    memUsage: MemUsage,

    info: union(enum) {
        imgInf: ImgInf,
        bufInf: BufInf,
    },
    pub const ImgInf = struct {
        extent: vk.VkExtent3D,
        imgFormat: c_uint = RENDER_IMG_FORMAT,
        arrayIndex: u32,
    };
    pub const BufInf = struct {
        sizeOfElement: u64 = 0,
        length: u32,
        bufUsage: enum { Storage, Uniform, Index, Vertex, Staging },
    };
    pub const MemUsage = enum { GpuOptimal, CpuWriteOptimal, CpuReadOptimal };
};

pub const DescBinding = union(enum) {
    pub const ImageArrayBinding = struct {
        binding: u32,
        arrayLength: u32,
    };
    pub const BufferBinding = struct {
        binding: u32,
    };
    imageArrayBinding: ImageArrayBinding,
    bufferBinding: BufferBinding,
};

pub const textureBinding = DescBinding{ .imageArrayBinding = .{ .binding = 0, .arrayLength = GPU_IMG_MAX } };
pub const objectBinding1 = DescBinding{ .bufferBinding = .{ .binding = 1 } };
pub const objectBinding2 = DescBinding{ .bufferBinding = .{ .binding = 2 } };
pub const bindingRegistry: []const DescBinding = &.{ textureBinding, objectBinding1, objectBinding2 };

pub const img1 = ResourceInfo{ .gpuId = 50, .binding = 0, .memUsage = .GpuOptimal, .info = .{ .imgInf = .{ .arrayIndex = 0, .extent = .{ .width = 500, .height = 500, .depth = 1 } } } };
pub const img2 = ResourceInfo{ .gpuId = 51, .binding = 0, .memUsage = .GpuOptimal, .info = .{ .imgInf = .{ .arrayIndex = 1, .extent = .{ .width = 300, .height = 300, .depth = 1 } } } };
pub const img3 = ResourceInfo{ .gpuId = 52, .binding = 0, .memUsage = .GpuOptimal, .info = .{ .imgInf = .{ .arrayIndex = 2, .extent = .{ .width = 100, .height = 100, .depth = 1 } } } };
pub const img4 = ResourceInfo{ .gpuId = 53, .binding = 0, .memUsage = .GpuOptimal, .info = .{ .imgInf = .{ .arrayIndex = 3, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } } } };
pub const img5 = ResourceInfo{ .gpuId = 54, .binding = 0, .memUsage = .GpuOptimal, .info = .{ .imgInf = .{ .arrayIndex = 4, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } } } };
pub const buff1 = ResourceInfo{ .gpuId = 1, .binding = 1, .memUsage = .CpuWriteOptimal, .info = .{ .bufInf = .{ .bufUsage = .Storage, .length = 1000, .sizeOfElement = @sizeOf(Object) } } };
pub const buff2 = ResourceInfo{ .gpuId = 0, .binding = 2, .memUsage = .CpuWriteOptimal, .info = .{ .bufInf = .{ .bufUsage = .Storage, .length = 100, .sizeOfElement = @sizeOf(Object) } } };

pub const pass1: Pass = .{ .passImgId = img1.gpuId, .shaderIds = &.{sc.t1Comp.id} }; // clear does not work for compute
pub const pass2: Pass = .{ .passImgId = img2.gpuId, .shaderIds = &.{ sc.t2Vert.id, sc.t2Frag.id } };
pub const pass3: Pass = .{ .passImgId = img3.gpuId, .shaderIds = &.{ sc.t3Mesh.id, sc.t3Frag.id } };
pub const pass4: Pass = .{ .passImgId = img4.gpuId, .shaderIds = &.{ sc.t4Task.id, sc.t4Mesh.id, sc.t4Frag.id } };
pub const pass5: Pass = .{ .passImgId = img4.gpuId, .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id }, .clear = true };

pub const renderSequence: []const Pass = &.{ pass1, pass2, pass3, pass4, pass5 };
