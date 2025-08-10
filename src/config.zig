pub const c = @import("c.zig");
pub const std = @import("std");
const KeyEvent = @import("platform/WindowManager.zig").KeyEvent;

// Debug
pub const DEBUG_MODE = true;
pub const CLOSE_WITH_CONSOLE = false;
pub const SHADER_HOTLOAD = true;

// Rendering, Swapchains and Windows
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 3;
pub const RENDER_IMAGE_PRESET: c.VkExtent3D = .{ .width = 1920, .height = 1080, .depth = 1 };
pub const DISPLAY_MODE = c.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const MAX_WINDOWS: u8 = 12;

// Camera
pub const CAM_SPEED = 0.00000001;
pub const CAM_SENS = 0.0003;
pub const CAM_INIT_FOV = 100;
pub const CAM_FOV_CHANGE = 0.0000001;

// KeyMap
pub const CAMERA_FORWARD_KEY: KeyEvent = .{ .key = c.SDLK_W, .event = .pressed };
pub const CAMERA_BACKWARD_KEY: KeyEvent = .{ .key = c.SDLK_S, .event = .pressed };
pub const CAMERA_LEFT_KEY: KeyEvent = .{ .key = c.SDLK_A, .event = .pressed };
pub const CAMERA_RIGHT_KEY: KeyEvent = .{ .key = c.SDLK_D, .event = .pressed };
pub const CAMERA_UP_KEY: KeyEvent = .{ .key = c.SDLK_Q, .event = .pressed };
pub const CAMERA_DOWN_KEY: KeyEvent = .{ .key = c.SDLK_E, .event = .pressed };
pub const CAMERA_FOV_INCREASE_KEY: KeyEvent = .{ .key = c.SDLK_1, .event = .pressed };
pub const CAMERA_FOV_DECREASE_KEY: KeyEvent = .{ .key = c.SDLK_2, .event = .pressed };

pub const CLOSE_KEY: KeyEvent = .{ .key = c.SDLK_ESCAPE, .event = .pressed };
pub const RESTART_KEY: KeyEvent = .{ .key = c.SDLK_R, .event = .pressed };
