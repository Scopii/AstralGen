pub const c = @import("c.zig");
pub const std = @import("std");
const KeyEvent = @import("platform/WindowManager.zig").KeyEvent;

// Debug
pub const DEBUG_MODE = true;
pub const CLOSE_WITH_CONSOLE = false;
pub const SHADER_HOTLOAD = true;

// Rendering
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 2;
pub const RENDER_IMAGE_PRESET: c.VkExtent3D = .{ .width = 1920, .height = 1080, .depth = 1 };

// Swapchain and Windows
pub const MAX_WINDOWS: u8 = 12;

// KeyMap
pub const CLOSE_KEY: KeyEvent = .{ .key = c.SDLK_ESCAPE, .event = .pressed };
pub const UPDATE_CAM_KEY: KeyEvent = .{ .key = c.SDLK_UP, .event = .pressed };
pub const RESTART_KEY: KeyEvent = .{ .key = c.SDLK_R, .event = .pressed };
