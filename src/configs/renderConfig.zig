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

pub const RenderType = enum { computePass, graphicsPass, meshPass, taskMeshPass, vertexPass };

pub const PassInfo = struct {
    renderImgId: u32,
    shaderIds: []const u8,
    clear: bool = false,
};

pub const MemUsage = enum { GpuOptimal, CpuWriteOptimal, CpuReadOptimal };

pub const ResourceState = struct { layout: vk.VkImageLayout, access: vk.VkAccessFlags, stage: vk.VkPipelineStageFlags }; // PREPARED FOR RENDER GRAPH

pub const ResourceSchema = union(enum) {
    pub const ImageResource = struct {
        binding: u8,
        resourceId: u32,
        extent: vk.VkExtent3D,
        imgFormat: c_uint = RENDER_IMG_FORMAT,
        memUsage: MemUsage,
    };
    pub const BufferResource = struct {
        binding: u8,
        elementSize: u64 = 0,
        length: u32,
        memUsage: MemUsage,
        buffUsage: enum { Storage, Uniform, Index, Vertex, Staging },
    };
    image: ImageResource,
    buffer: BufferResource,
};

pub const BindingSchema = union(enum) {
    pub const ImageArrayBinding = struct {
        binding: u8,
        arrayLength: u32,
    };
    pub const BufferBinding = struct {
        binding: u8,
    };
    imageArrayBinding: ImageArrayBinding,
    bufferBinding: BufferBinding,
};

pub const textureBinding = BindingSchema{ .imageArrayBinding = .{ .binding = 0, .arrayLength = GPU_IMG_MAX } };
pub const objectBinding1 = BindingSchema{ .bufferBinding = .{ .binding = 1 } };
pub const objectBinding2 = BindingSchema{ .bufferBinding = .{ .binding = 2 } };
pub const resourceRegistry: []const BindingSchema = &.{ textureBinding, objectBinding1, objectBinding2 };

pub const imgResource1 = ResourceSchema{ .image = .{ .binding = 0, .resourceId = 50, .memUsage = .GpuOptimal, .extent = .{ .width = 500, .height = 500, .depth = 1 } } };
pub const imgResource2 = ResourceSchema{ .image = .{ .binding = 0, .resourceId = 51, .memUsage = .GpuOptimal, .extent = .{ .width = 300, .height = 300, .depth = 1 } } };
pub const imgResource3 = ResourceSchema{ .image = .{ .binding = 0, .resourceId = 52, .memUsage = .GpuOptimal, .extent = .{ .width = 100, .height = 100, .depth = 1 } } };
pub const imgResource4 = ResourceSchema{ .image = .{ .binding = 0, .resourceId = 53, .memUsage = .GpuOptimal, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } } };
pub const imgResource5 = ResourceSchema{ .image = .{ .binding = 0, .resourceId = 54, .memUsage = .GpuOptimal, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } } };
pub const buffer1 = ResourceSchema{ .buffer = .{ .binding = 1, .elementSize = @sizeOf(Object), .length = 1000, .memUsage = .CpuWriteOptimal, .buffUsage = .Storage } };
pub const buffer2 = ResourceSchema{ .buffer = .{ .binding = 2, .elementSize = @sizeOf(Object), .length = 100, .memUsage = .CpuWriteOptimal, .buffUsage = .Storage } };

pub const pass1: PassInfo = .{ .renderImgId = imgResource1.image.resourceId, .shaderIds = &.{sc.t1Comp.id} }; // clear does not work for compute
pub const pass2: PassInfo = .{ .renderImgId = imgResource2.image.resourceId, .shaderIds = &.{ sc.t2Vert.id, sc.t2Frag.id } };
pub const pass3: PassInfo = .{ .renderImgId = imgResource3.image.resourceId, .shaderIds = &.{ sc.t3Mesh.id, sc.t3Frag.id } };
pub const pass4: PassInfo = .{ .renderImgId = imgResource4.image.resourceId, .shaderIds = &.{ sc.t4Task.id, sc.t4Mesh.id, sc.t4Frag.id } };
pub const pass5: PassInfo = .{ .renderImgId = imgResource4.image.resourceId, .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id }, .clear = true };

pub const renderSequence: []const PassInfo = &.{ pass1, pass2, pass3, pass4, pass5 };
