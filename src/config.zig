pub const c = @import("c.zig");
pub const std = @import("std");
const KeyAssignments = @import("core/EventManager.zig").KeyAssignments;
const ShaderInfo = @import("vulkan/ShaderPipeline.zig").ShaderInfo;

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
pub const glslPath: []const u8 = "/src/shader";
pub const sprvPath: []const u8 = "/zig-out/shader";

pub const Shader = struct {
    stage: c.VkShaderStageFlagBits,
    glslFile: []const u8,
    spvFile: []const u8,
};

pub const ShaderLayout = struct {
    shaders: []const Shader,
    renderPass: RenderPass,
};
// Render
pub const comp1 = Shader{ .stage = c.VK_SHADER_STAGE_COMPUTE_BIT, .glslFile = "Compute.comp", .spvFile = "Compute.spv" };
pub const vert1 = Shader{ .stage = c.VK_SHADER_STAGE_VERTEX_BIT, .glslFile = "Graphics.vert", .spvFile = "GraphicsVert.spv" };
pub const frag1 = Shader{ .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .glslFile = "Graphics.frag", .spvFile = "GraphicsFrag.spv" };
pub const mesh1 = Shader{ .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT, .glslFile = "Mesh.mesh", .spvFile = "MeshMesh.spv" };
pub const frag2 = Shader{ .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .glslFile = "Mesh.frag", .spvFile = "MeshFrag.spv" };

pub const computePass1: ShaderLayout = .{ .renderPass = .compute, .shaders = .{comp1} };
pub const graphicsPass1: ShaderLayout = .{ .renderPass = .graphics1, .shaders = .{ vert1, frag1 } };
pub const meshPass1: ShaderLayout = .{ .renderPass = .mesh1, .shaders = .{ mesh1, frag2 } };

pub const renderPassSequence: []const ShaderLayout = .{
    computePass1,
    graphicsPass1,
    meshPass1,
};

// Render
pub const computePipe1 = [_]ShaderInfo{
    .{ .renderType = .compute, .renderPass = .compute1, .stage = c.VK_SHADER_STAGE_COMPUTE_BIT, .glslFile = "Compute.comp", .spvFile = "Compute.spv" },
};
pub const computePipe2 = [_]ShaderInfo{
    .{ .renderType = .compute, .renderPass = .graphics1, .stage = c.VK_SHADER_STAGE_COMPUTE_BIT, .glslFile = "Compute.comp", .spvFile = "Compute.spv" },
};
pub const graphicsPipe1 = [_]ShaderInfo{
    .{ .renderType = .graphics, .renderPass = .graphics1, .stage = c.VK_SHADER_STAGE_VERTEX_BIT, .glslFile = "Graphics.vert", .spvFile = "GraphicsVert.spv" },
    .{ .renderType = .graphics, .renderPass = .graphics1, .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .glslFile = "Graphics.frag", .spvFile = "GraphicsFrag.spv" },
};
pub const meshPipe1 = [_]ShaderInfo{
    .{ .renderType = .mesh, .renderPass = .mesh1, .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT, .glslFile = "Mesh.mesh", .spvFile = "MeshMesh.spv" },
    .{ .renderType = .mesh, .renderPass = .mesh1, .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .glslFile = "Mesh.frag", .spvFile = "MeshFrag.spv" },
};
pub const renderSequence: []const []const ShaderInfo = &.{
    &computePipe1,
    &graphicsPipe1,
    &meshPipe1,
    &computePipe2,
};

pub const ComputeConfig = struct {
    shader: []const u8, // One file. Mandatory.
    dispatch: [3]u32 = .{ 0, 1, 1 }, // 0 means "screen/grid dependent"
};

pub const GraphicsConfig = struct {
    vertex: []const u8, // Mandatory
    fragment: []const u8, // Mandatory
    // No compute field exists here!
};

pub const MeshConfig = struct {
    task: ?[]const u8 = null, // Optional
    mesh: []const u8, // Mandatory
    fragment: []const u8, // Mandatory
};

// The Union enforces that a pass is EXACTLY one of these valid types
pub const PassType = union(enum) {
    Compute: ComputeConfig,
    Graphics: GraphicsConfig,
    Mesh: MeshConfig,
};

pub const RenderPass = struct {
    name: []const u8,
    action: PassType, // The logic
    barrier: bool = false, // Simple safety switch
};
