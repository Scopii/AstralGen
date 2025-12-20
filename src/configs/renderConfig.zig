const vk = @import("../modules/vk.zig").c;
const Object = @import("../ecs/EntityManager.zig").Object;
const sc = @import("shaderConfig.zig");
const ShaderStage = @import("../vulkan/ShaderObject.zig").ShaderStage;

// Rendering, Swapchains and Windows
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = vk.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const MAX_WINDOWS: u8 = 16;

pub const GPU_IMG_MAX = 64;
pub const RENDER_IMG_FORMAT = vk.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const RENDER_IMG_AUTO_RESIZE = true;
pub const RENDER_IMG_STRETCH = true; // Ignored on AUTO_RESIZE

pub const RenderType = enum { computePass, graphicsPass, meshPass, taskMeshPass, vertexPass };

pub const PassInfo = struct {
    renderImg: ResourceInfo,
    shaderIds: []const u8,
    clear: bool = false,
};
// Render

pub const MemUsage = enum { GpuOptimal, CpuWriteOptimal, CpuReadOptimal };

pub const ResourceInfo = struct {
    binding: u8,
    resourceId: u32,
    resourceType: enum { Image, Data },

    //Image Specific
    extent: vk.VkExtent3D,
    imgFormat: c_uint = RENDER_IMG_FORMAT,
    memUsage: MemUsage,

    //Buffer Specific
    //bufferData: type,
};

pub const BindingInfo = struct {
    binding: u8,
    length: u32,
    bindingType: enum { Image, Buffer },
    memUsage: MemUsage,

    //Buffer specific
    buffUsage: enum { Storage, Uniform, Index, Vertex, Staging, None } = .None,
    elementSize: u64 = 0,
};

pub const textureBinding = BindingInfo{ .binding = 0, .length = GPU_IMG_MAX, .memUsage = .CpuWriteOptimal, .bindingType = .Image };
pub const objectBinding = BindingInfo{ .binding = 1, .length = 1000, .memUsage = .CpuWriteOptimal, .bindingType = .Buffer, .buffUsage = .Storage, .elementSize = @sizeOf(Object) };
pub const objectBinding2 = BindingInfo{ .binding = 2, .length = 100, .memUsage = .CpuWriteOptimal, .bindingType = .Buffer, .buffUsage = .Storage, .elementSize = @sizeOf(Object) };
pub const resourceRegistry: []const BindingInfo = &.{ textureBinding, objectBinding, objectBinding2 };

//pub const GPU_BINDING_COUNT = resourceRegistry.len;
pub const GPU_BUF_COUNT = 2; // SHOULD BE DYNAMICALLY DONE! NEEDED FOR BUFFER MANAGER

pub const imgResource1 = ResourceInfo{ .binding = 0, .resourceId = 50, .resourceType = .Image, .memUsage = .GpuOptimal, .extent = .{ .width = 500, .height = 500, .depth = 1 } };
pub const imgResource2 = ResourceInfo{ .binding = 0, .resourceId = 51, .resourceType = .Image, .memUsage = .GpuOptimal, .extent = .{ .width = 300, .height = 300, .depth = 1 } };
pub const imgResource3 = ResourceInfo{ .binding = 0, .resourceId = 52, .resourceType = .Image, .memUsage = .GpuOptimal, .extent = .{ .width = 100, .height = 100, .depth = 1 } };
pub const imgResource4 = ResourceInfo{ .binding = 0, .resourceId = 53, .resourceType = .Image, .memUsage = .GpuOptimal, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } };
pub const imgResource5 = ResourceInfo{ .binding = 0, .resourceId = 54, .resourceType = .Image, .memUsage = .GpuOptimal, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } };

pub const pass1: PassInfo = .{ .renderImg = imgResource1, .shaderIds = &.{sc.t1Comp.id} }; // clear does not work for compute
pub const pass2: PassInfo = .{ .renderImg = imgResource2, .shaderIds = &.{ sc.t2Vert.id, sc.t2Frag.id } };
pub const pass3: PassInfo = .{ .renderImg = imgResource3, .shaderIds = &.{ sc.t3Mesh.id, sc.t3Frag.id } };
pub const pass4: PassInfo = .{ .renderImg = imgResource4, .shaderIds = &.{ sc.t4Task.id, sc.t4Mesh.id, sc.t4Frag.id } };
pub const pass5: PassInfo = .{ .renderImg = imgResource4, .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id }, .clear = true };

pub const renderSequence: []const PassInfo = &.{ pass1, pass2, pass3, pass4, pass5 };
