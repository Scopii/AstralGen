pub const c = @import("c.zig");
pub const std = @import("std");
const KeyMapping = @import("core/EventManager.zig").KeyMapping;

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
pub const MAX_WINDOWS: u8 = 16; // u64 is set as Max Bitmask in Draw so no bigger than that!

pub const RENDER_IMG_MAX = 64;
pub const RENDER_IMG_AUTO_RESIZE = true;
pub const RENDER_IMG_FORMAT = c.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const RENDER_IMG_EXTENT1: c.VkExtent3D = .{ .width = 1920, .height = 1080, .depth = 1 };
pub const RENDER_IMG_EXTENT2: c.VkExtent3D = .{ .width = 100, .height = 100, .depth = 1 };
pub const RENDER_IMG_EXTENT3: c.VkExtent3D = .{ .width = 5, .height = 5, .depth = 1 };
pub const RENDER_IMG_STRETCH = false;

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
pub const keyMap = [_]KeyMapping{
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
    renderImg: RenderResource,
    shaders: []const Shader,
    clear: bool,
};

pub const RenderType = enum { compute, graphics, mesh, taskMesh, vertOnly };
pub const RenderResource = struct {
    id: u8,
    extent: c.VkExtent3D,
    imgFormat: c_uint,
    memUsage: c_uint,
};

// Render
pub const comp1 = Shader{ .stage = c.VK_SHADER_STAGE_COMPUTE_BIT, .glslFile = "Compute.comp", .spvFile = "Compute.spv" };

pub const vert1 = Shader{ .stage = c.VK_SHADER_STAGE_VERTEX_BIT, .glslFile = "Graphics.vert", .spvFile = "GraphicsVert.spv" };
pub const frag1 = Shader{ .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .glslFile = "Graphics.frag", .spvFile = "GraphicsFrag.spv" };

pub const mesh1 = Shader{ .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT, .glslFile = "Mesh.mesh", .spvFile = "MeshMesh.spv" };
pub const frag2 = Shader{ .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .glslFile = "Mesh.frag", .spvFile = "MeshFrag.spv" };

pub const task1 = Shader{ .stage = c.VK_SHADER_STAGE_TASK_BIT_EXT, .glslFile = "TaskMesh.task", .spvFile = "TaskMeshTask.spv" };
pub const mesh2 = Shader{ .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT, .glslFile = "TaskMesh.mesh", .spvFile = "TaskMeshMesh.spv" };
pub const frag3 = Shader{ .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .glslFile = "TaskMesh.frag", .spvFile = "TaskMeshFrag.spv" };

pub const shadersToCompile: []const Shader = &.{ comp1, vert1, frag1, mesh1, frag2, task1, mesh2, frag3 };

pub const renderImg1 = RenderResource{ .id = 0, .extent = RENDER_IMG_EXTENT1, .imgFormat = RENDER_IMG_FORMAT, .memUsage = c.VMA_MEMORY_USAGE_GPU_ONLY };
pub const renderImg2 = RenderResource{ .id = 1, .extent = RENDER_IMG_EXTENT2, .imgFormat = RENDER_IMG_FORMAT, .memUsage = c.VMA_MEMORY_USAGE_GPU_ONLY };
pub const renderImg3 = RenderResource{ .id = 15, .extent = RENDER_IMG_EXTENT3, .imgFormat = RENDER_IMG_FORMAT, .memUsage = c.VMA_MEMORY_USAGE_GPU_ONLY };
pub const renderImg4 = RenderResource{ .id = 7, .extent = RENDER_IMG_EXTENT3, .imgFormat = RENDER_IMG_FORMAT, .memUsage = c.VMA_MEMORY_USAGE_GPU_ONLY };

pub const computePass1: ShaderLayout = .{ .renderImg = renderImg1, .shaders = &.{comp1}, .clear = true }; // clear does not work for compute
pub const graphicsPass1: ShaderLayout = .{ .renderImg = renderImg2, .shaders = &.{ vert1, frag1 }, .clear = false };
pub const meshPass1: ShaderLayout = .{ .renderImg = renderImg3, .shaders = &.{ mesh1, frag2 }, .clear = false };
pub const taskMeshPass1: ShaderLayout = .{ .renderImg = renderImg4, .shaders = &.{ task1, mesh2, frag3 }, .clear = false };

pub const renderSeq: []const ShaderLayout = &.{
    graphicsPass1,
    meshPass1,
    computePass1,
    taskMeshPass1,
};
