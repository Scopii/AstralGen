const c = @import("c");
pub const std = @import("std");
const KeyMapping = @import("core/EventManager.zig").KeyMapping;
const ShaderStage = @import("vulkan/ShaderObject.zig").ShaderStage;

// Vulkan Validation Layers
pub const DEBUG_MODE = true;
pub const EXTRA_VALIDATION = false;
pub const BEST_PRACTICES = false;

// Shader Compilation
pub const SHADER_HOTLOAD = false;
pub const SHADER_STARTUP_COMPILATION = true;
pub const SHADER_MAX = 100;

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
pub const RENDER_IMG_FORMAT = c.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const RENDER_IMG_AUTO_RESIZE = true;
pub const RENDER_IMG_STRETCH = true; // Ignored on AUTO_RESIZE

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

pub const ShaderType = enum {
    compute,
    vert,
    frag,
    task,
    mesh,
    meshNoTask,
};

pub const ShaderConfig = struct {
    id: u32,
    shaderType: ShaderType,
    timeStamp: i128 = 0,
    glslFile: []const u8,
    spvFile: []const u8,
};

pub const ShaderLayout = struct {
    renderImg: RenderResource,
    shaders: []const ShaderConfig,
    clear: bool = false,
};

pub const RenderType = enum { computePass, graphicsPass, meshPass, taskMeshPass, vertexPass };

pub const RenderResource = struct {
    id: u8,
    extent: c.VkExtent3D,
    imgFormat: c_uint = RENDER_IMG_FORMAT,
    memUsage: c_uint = c.VMA_MEMORY_USAGE_GPU_ONLY,
};

pub const PassConfig = struct {
    renderImg: RenderResource,
    shaderIds: []const u8,
    clear: bool = false,
};

// Render
pub const comp1 = ShaderConfig{ .id = 0, .shaderType = .compute, .glslFile = "compTest/comp.slang", .spvFile = "comp1.spv" };
pub const renderImg1 = RenderResource{ .id = 0, .extent = .{ .width = 500, .height = 500, .depth = 1 } };
pub const pass1: PassConfig = .{ .renderImg = renderImg1, .shaderIds = &.{comp1.id} }; // clear does not work for compute

pub const vert1 = ShaderConfig{ .id = 1, .shaderType = .vert, .glslFile = "grapTest/vert.slang", .spvFile = "vert1.spv" };
pub const frag1 = ShaderConfig{ .id = 2, .shaderType = .frag, .glslFile = "grapTest/frag.slang", .spvFile = "frag1.spv" };
pub const renderImg2 = RenderResource{ .id = 1, .extent = .{ .width = 300, .height = 300, .depth = 1 } };
pub const pass2: PassConfig = .{ .renderImg = renderImg2, .shaderIds = &.{ vert1.id, frag1.id } };

pub const mesh1 = ShaderConfig{ .id = 3, .shaderType = .meshNoTask, .glslFile = "meshTest/mesh.slang", .spvFile = "mesh1.spv" };
pub const frag2 = ShaderConfig{ .id = 4, .shaderType = .frag, .glslFile = "meshTest/frag.slang", .spvFile = "frag2.spv" };
pub const renderImg3 = RenderResource{ .id = 15, .extent = .{ .width = 100, .height = 100, .depth = 1 } };
pub const pass3: PassConfig = .{ .renderImg = renderImg3, .shaderIds = &.{ mesh1.id, frag2.id } };

pub const task1 = ShaderConfig{ .id = 5, .shaderType = .task, .glslFile = "taskTest/task.slang", .spvFile = "task1.spv" };
pub const mesh2 = ShaderConfig{ .id = 6, .shaderType = .mesh, .glslFile = "taskTest/mesh.slang", .spvFile = "mesh2.spv" };
pub const frag3 = ShaderConfig{ .id = 7, .shaderType = .frag, .glslFile = "taskTest/frag.slang", .spvFile = "frag3.spv" };
pub const renderImg4 = RenderResource{ .id = 7, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } };
pub const pass4: PassConfig = .{ .renderImg = renderImg4, .shaderIds = &.{ task1.id, mesh2.id, frag3.id } };

pub const task2 = ShaderConfig{ .id = 8, .shaderType = .task, .glslFile = "gridTest/task.slang", .spvFile = "task2.spv" };
pub const mesh3 = ShaderConfig{ .id = 9, .shaderType = .mesh, .glslFile = "gridTest/mesh.slang", .spvFile = "mesh3.spv" };
pub const frag4 = ShaderConfig{ .id = 10, .shaderType = .frag, .glslFile = "gridTest/frag.slang", .spvFile = "frag4.spv" };
pub const renderImg5 = RenderResource{ .id = 7, .extent = .{ .width = 1920, .height = 1080, .depth = 1 } };
pub const pass5: PassConfig = .{ .renderImg = renderImg4, .shaderIds = &.{ task2.id, mesh3.id, frag4.id }, .clear = true };

pub const shadersToCompile: []const ShaderConfig = &.{ comp1, vert1, frag1, mesh1, frag2, task1, mesh2, frag3, task2, mesh3, frag4 };

pub const renderSeq2: []const PassConfig = &.{
    pass1,
    pass2,
    pass3,
    pass4,
    pass5,
};
