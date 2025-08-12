pub const c = @import("c.zig");
pub const std = @import("std");
const KeyEvent = @import("core/EventManager.zig").KeyEvent;
const KeyState = @import("core/EventManager.zig").KeyState;
const AppEvent = @import("core/EventManager.zig").AppEvent;
const ShaderInfo = @import("vulkan/PipelineBucket.zig").ShaderInfo;

// Debug
pub const DEBUG_MODE = true;
pub const CLOSE_WITH_CONSOLE = false;
pub const SHADER_HOTLOAD = true;
pub const SHADER_STARTUP_COMPILATION = true;

// Rendering, Swapchains and Windows
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const RENDER_IMAGE_PRESET: c.VkExtent3D = .{ .width = 2, .height = 2, .depth = 1 };
pub const RENDER_IMAGE_FORMAT = c.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const DISPLAY_MODE = c.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const MAX_WINDOWS: u8 = 12;

// Camera
pub const CAM_SPEED = 0.00000001;
pub const CAM_SENS = 0.0003;
pub const CAM_INIT_FOV = 100;
pub const CAM_FOV_CHANGE = 0.0000001;

pub const KeyAssignments = struct {
    device: enum { mouse, keyboard },
    state: KeyState,
    cycle: enum { oneTime, repeat },
    appEvent: AppEvent,
    key: c_uint,
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

    // Mouse
    .{ .device = .mouse, .state = .pressed, .cycle = .repeat, .key = c.SDL_BUTTON_LEFT, .appEvent = .camForward },
};

// Paths
pub const rootPath: []const u8 = "../..";
pub const shaderPath: []const u8 = "/src/shader";
pub const shaderOutputPath: []const u8 = "/zig-out/shader";

pub const shaderInfos = [_]ShaderInfo{
    .{ .pipeType = .compute, .stage = c.VK_SHADER_STAGE_COMPUTE_BIT, .inputName = "Compute.comp", .outputName = "Compute.spv" },

    .{ .pipeType = .graphics, .stage = c.VK_SHADER_STAGE_VERTEX_BIT, .inputName = "Graphics.vert", .outputName = "GraphicsVert.spv" },
    .{ .pipeType = .graphics, .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .inputName = "Graphics.frag", .outputName = "GraphicsFrag.spv" },

    .{ .pipeType = .mesh, .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT, .inputName = "Mesh.mesh", .outputName = "MeshMesh.spv" },
    .{ .pipeType = .mesh, .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .inputName = "Mesh.frag", .outputName = "MeshFrag.spv" },
};

// Shader Infos
pub const computeInf = [_]ShaderInfo{
    .{ .pipeType = .compute, .stage = c.VK_SHADER_STAGE_COMPUTE_BIT, .inputName = "src/shader/Compute.comp", .outputName = "shader/Compute.spv" },
};
pub const graphicsInf = [_]ShaderInfo{
    .{ .pipeType = .graphics, .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .inputName = "src/shader/Graphics.frag", .outputName = "shader/GraphicsFrag.spv" },
    .{ .pipeType = .graphics, .stage = c.VK_SHADER_STAGE_VERTEX_BIT, .inputName = "src/shader/Graphics.vert", .outputName = "shader/GraphicsVert.spv" },
};
pub const meshShaderInf = [_]ShaderInfo{
    .{ .pipeType = .mesh, .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .inputName = "src/shader/Mesh.frag", .outputName = "shader/MeshFrag.spv" },
    .{ .pipeType = .mesh, .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT, .inputName = "src/shader/Mesh.mesh", .outputName = "shader/MeshMesh.spv" },
};
