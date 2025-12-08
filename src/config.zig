pub const c = @import("c.zig");
pub const std = @import("std");
const KeyAssignments = @import("core/EventManager.zig").KeyAssignments;

// Vulkan Validation Layers
pub const DEBUG_MODE = true;
pub const EXTRA_VALIDATION = false;
pub const BEST_PRACTICES = false;

// Shader Compilation
pub const SHADER_HOTLOAD = true;
pub const SHADER_STARTUP_COMPILATION = true;

// Dev Mode
pub const CLOSE_WITH_CONSOLE = false;
pub const MOUSE_MOVEMENT_INFO = false;
pub const KEY_EVENT_INFO = false;

// Rendering, Swapchains and Windows
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = c.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const MAX_WINDOWS: u8 = 64; // u64 is set as Max Bitmask in Draw so no bigger than that!

pub const RENDER_IMAGE_PRESET: c.VkExtent3D = .{ .width = 1920, .height = 1080, .depth = 1 };
pub const RENDER_IMAGE_AUTO_RESIZE = true;
pub const RENDER_IMAGE_FORMAT = c.VK_FORMAT_R16G16B16A16_SFLOAT;

pub const RENDER_IMAGE_PRESET2: c.VkExtent3D = .{ .width = 100, .height = 100, .depth = 1 };
pub const RENDER_IMAGE_PRESET3: c.VkExtent3D = .{ .width = 5, .height = 5, .depth = 1 };

// Camera
pub const CAM_SPEED = 0.00000001;
pub const CAM_SENS = 0.0003;
pub const CAM_INIT_FOV = 100;
pub const CAM_FOV_CHANGE = 0.0000001;

// All Events of the Application
pub const AppEvent = enum {
    camForward,
    camBackward,
    camLeft,
    camRight,
    camUp,
    camDown,
    camFovIncrease,
    camFovDecrease,

    toggleFullscreen,
    closeApp,
    restartApp,
};

// KeyMap
pub const keyAssignments = [_]KeyAssignments{
    // Camera
    .{ .device = .keyboard, .state = .pressed, .cycle = .repeat, .key = c.SDL_SCANCODE_W, .appEvent = .camForward },
    .{ .device = .keyboard, .state = .pressed, .cycle = .repeat, .key = c.SDL_SCANCODE_S, .appEvent = .camBackward },
    .{ .device = .keyboard, .state = .pressed, .cycle = .repeat, .key = c.SDL_SCANCODE_A, .appEvent = .camLeft },
    .{ .device = .keyboard, .state = .pressed, .cycle = .repeat, .key = c.SDL_SCANCODE_D, .appEvent = .camRight },
    .{ .device = .keyboard, .state = .pressed, .cycle = .repeat, .key = c.SDL_SCANCODE_Q, .appEvent = .camUp },
    .{ .device = .keyboard, .state = .pressed, .cycle = .repeat, .key = c.SDL_SCANCODE_E, .appEvent = .camDown },
    .{ .device = .keyboard, .state = .pressed, .cycle = .repeat, .key = c.SDL_SCANCODE_DOWN, .appEvent = .camFovIncrease },
    .{ .device = .keyboard, .state = .pressed, .cycle = .repeat, .key = c.SDL_SCANCODE_UP, .appEvent = .camFovDecrease },
    // App Control
    .{ .device = .keyboard, .state = .pressed, .cycle = .oneTime, .key = c.SDL_SCANCODE_ESCAPE, .appEvent = .closeApp },
    .{ .device = .keyboard, .state = .pressed, .cycle = .oneTime, .key = c.SDL_SCANCODE_R, .appEvent = .restartApp },
    .{ .device = .keyboard, .state = .pressed, .cycle = .oneTime, .key = c.SDL_SCANCODE_LCTRL, .appEvent = .toggleFullscreen },
    // Mouse
    .{ .device = .mouse, .state = .pressed, .cycle = .repeat, .key = c.SDL_BUTTON_LEFT, .appEvent = .camForward },
};

// Paths
pub const rootPath: []const u8 = "../..";
pub const glslPath: []const u8 = "/src/shader";
pub const sprvPath: []const u8 = "/zig-out/shader";

pub const Shader = struct {
    stage: c.VkShaderStageFlagBits,
    glslFile: []const u8,
    spvFile: []const u8,
};

pub const ShaderLayout = struct {
    renderImage: RenderResource,
    shaders: []const Shader,
    clear: bool,
};

pub const RenderType = enum { compute, graphics, mesh, taskMesh, vertOnly };
pub const RenderResource = struct {
    id: u8,
    dimensions: c.VkExtent3D,
    imageFormat: c_uint,
    memoryUsage: c_uint,
};

pub const renderImage1 = RenderResource{ .id = 0, .dimensions = RENDER_IMAGE_PRESET, .imageFormat = RENDER_IMAGE_FORMAT, .memoryUsage = c.VMA_MEMORY_USAGE_GPU_ONLY };
pub const renderImage2 = RenderResource{ .id = 1, .dimensions = RENDER_IMAGE_PRESET2, .imageFormat = RENDER_IMAGE_FORMAT, .memoryUsage = c.VMA_MEMORY_USAGE_GPU_ONLY };
pub const renderImage3 = RenderResource{ .id = 2, .dimensions = RENDER_IMAGE_PRESET3, .imageFormat = RENDER_IMAGE_FORMAT, .memoryUsage = c.VMA_MEMORY_USAGE_GPU_ONLY };

// Render
pub const comp1 = Shader{ .stage = c.VK_SHADER_STAGE_COMPUTE_BIT, .glslFile = "Compute.comp", .spvFile = "Compute.spv" };
pub const vert1 = Shader{ .stage = c.VK_SHADER_STAGE_VERTEX_BIT, .glslFile = "Graphics.vert", .spvFile = "GraphicsVert.spv" };
pub const frag1 = Shader{ .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .glslFile = "Graphics.frag", .spvFile = "GraphicsFrag.spv" };
pub const mesh1 = Shader{ .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT, .glslFile = "Mesh.mesh", .spvFile = "MeshMesh.spv" };
pub const frag2 = Shader{ .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .glslFile = "Mesh.frag", .spvFile = "MeshFrag.spv" };

pub const shadersToCompile: []const Shader = &.{ comp1, vert1, frag1, mesh1, frag2 };

pub const computePass1: ShaderLayout = .{ .renderImage = renderImage1, .shaders = &.{comp1}, .clear = true }; // clear does not work for compute
pub const graphicsPass1: ShaderLayout = .{ .renderImage = renderImage2, .shaders = &.{ vert1, frag1 }, .clear = false };
pub const meshPass1: ShaderLayout = .{ .renderImage = renderImage3, .shaders = &.{ mesh1, frag2 }, .clear = false };

pub const renderSeq: []const ShaderLayout = &.{
    computePass1,
    graphicsPass1,
    meshPass1,
};
