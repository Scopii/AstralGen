pub const c = @import("c.zig");
pub const std = @import("std");
const KeyAssignments = @import("core/EventManager.zig").KeyAssignments;
const ShaderInfo = @import("vulkan/PipelineBucket.zig").ShaderInfo;
const PipelineInfo = @import("vulkan/PipelineBucket.zig").PipelineInfo;

// Vulkan Validation Layers
pub const DEBUG_MODE = true;
pub const EXTRA_VALIDATION = false;
pub const BEST_PRACTICES = false;

// Dev Mode
pub const CLOSE_WITH_CONSOLE = false;
pub const SHADER_HOTLOAD = true;
pub const SHADER_STARTUP_COMPILATION = true;

// Rendering, Swapchains and Windows
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const DISPLAY_MODE = c.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const MAX_WINDOWS: u8 = 12;

pub const RENDER_IMAGE_PRESET: c.VkExtent3D = .{ .width = 1920, .height = 1080, .depth = 1 };
pub const RENDER_IMAGE_AUTO_RESIZE = true;
pub const RENDER_IMAGE_FORMAT = c.VK_FORMAT_R16G16B16A16_SFLOAT;

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
pub const shaderPath: []const u8 = "/src/shader";
pub const shaderOutputPath: []const u8 = "/zig-out/shader";

pub const shaderInfos = [_]ShaderInfo{
    .{ .pipeType = .compute, .inputName = "Compute.comp", .outputName = "Compute.spv" },

    .{ .pipeType = .graphics, .inputName = "Graphics.vert", .outputName = "GraphicsVert.spv" },
    .{ .pipeType = .graphics, .inputName = "Graphics.frag", .outputName = "GraphicsFrag.spv" },

    .{ .pipeType = .mesh, .inputName = "Mesh.mesh", .outputName = "MeshMesh.spv" },
    .{ .pipeType = .mesh, .inputName = "Mesh.frag", .outputName = "MeshFrag.spv" },
};

// Shader Infos
pub const computePipeInf = [_]PipelineInfo{
    .{ .pipeType = .compute, .stage = c.VK_SHADER_STAGE_COMPUTE_BIT, .sprvPath = "shader/Compute.spv" },
};
pub const graphicsPipeInf = [_]PipelineInfo{
    .{ .pipeType = .graphics, .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .sprvPath = "shader/GraphicsFrag.spv" },
    .{ .pipeType = .graphics, .stage = c.VK_SHADER_STAGE_VERTEX_BIT, .sprvPath = "shader/GraphicsVert.spv" },
};
pub const meshPipeInf = [_]PipelineInfo{
    .{ .pipeType = .mesh, .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .sprvPath = "shader/MeshFrag.spv" },
    .{ .pipeType = .mesh, .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT, .sprvPath = "shader/MeshMesh.spv" },
};
