pub const c = @import("c.zig");
pub const std = @import("std");
const KeyMapping = @import("core/EventManager.zig").KeyMapping;
const ShaderStage = @import("vulkan/ShaderObject.zig").ShaderStage;

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
pub const MAX_WINDOWS: u8 = 16;

pub const RENDER_IMG_MAX = 64;
pub const RENDER_IMG_AUTO_RESIZE = true;
pub const RENDER_IMG_FORMAT = c.VK_FORMAT_R16G16B16A16_SFLOAT;
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
    stage: ShaderStage,
    glslFile: []const u8,
    spvFile: []const u8,
};

pub const ShaderLayout = struct {
    renderImg: RenderResource,
    shaders: []const Shader,
    clear: bool = false,
};

pub const RenderType = enum { computePass, graphicsPass, meshPass, taskMeshPass, vertexPass };

pub const RenderResource = struct {
    id: u8,
    extent: c.VkExtent3D,
    imgFormat: c_uint = RENDER_IMG_FORMAT,
    memUsage: c_uint = c.VMA_MEMORY_USAGE_GPU_ONLY,
};

// Render
pub const comp1 = Shader{ .stage = .compute, .glslFile = "Compute.comp", .spvFile = "Compute.spv" };
pub const renderImg1 = RenderResource{ .id = 0, .extent = .{ .width = 500, .height = 500, .depth = 1 } };
pub const computePass1: ShaderLayout = .{ .renderImg = renderImg1, .shaders = &.{comp1} }; // clear does not work for compute

pub const vert1 = Shader{ .stage = .vertex, .glslFile = "Graphics.vert", .spvFile = "GraphicsVert.spv" };
pub const frag1 = Shader{ .stage = .frag, .glslFile = "Graphics.frag", .spvFile = "GraphicsFrag.spv" };
pub const renderImg2 = RenderResource{ .id = 1, .extent = .{ .width = 300, .height = 300, .depth = 1 } };
pub const graphicsPass1: ShaderLayout = .{ .renderImg = renderImg2, .shaders = &.{ vert1, frag1 } };

pub const mesh1 = Shader{ .stage = .mesh, .glslFile = "Mesh.mesh", .spvFile = "MeshMesh.spv" };
pub const frag2 = Shader{ .stage = .frag, .glslFile = "Mesh.frag", .spvFile = "MeshFrag.spv" };
pub const renderImg3 = RenderResource{ .id = 15, .extent = .{ .width = 100, .height = 100, .depth = 1 } };
pub const meshPass1: ShaderLayout = .{ .renderImg = renderImg3, .shaders = &.{ mesh1, frag2 } };

pub const task1 = Shader{ .stage = .task, .glslFile = "TaskMesh.task", .spvFile = "TaskMeshTask.spv" };
pub const mesh2 = Shader{ .stage = .mesh, .glslFile = "TaskMesh.mesh", .spvFile = "TaskMeshMesh.spv" };
pub const frag3 = Shader{ .stage = .frag, .glslFile = "TaskMesh.frag", .spvFile = "TaskMeshFrag.spv" };
pub const renderImg4 = RenderResource{ .id = 7, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } };
pub const taskMeshPass1: ShaderLayout = .{ .renderImg = renderImg4, .shaders = &.{ task1, mesh2, frag3 } };

pub const renderSeq: []const ShaderLayout = &.{
    graphicsPass1,
    meshPass1,
    computePass1,
    taskMeshPass1,
};

pub const shadersToCompile: []const Shader = &.{ comp1, vert1, frag1, mesh1, frag2, task1, mesh2, frag3 };
