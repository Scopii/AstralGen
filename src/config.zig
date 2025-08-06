pub const c = @import("c.zig");

// Debug
pub const DEBUG_MODE = true;
pub const CLOSE_WITH_CONSOLE = false;
pub const SHADER_HOTLOAD = true;

// Rendering
pub const MAX_IN_FLIGHT: u8 = 2; // (Frames)
pub const DESIRED_SWAPCHAIN_IMAGES: u8 = 2;
pub const RENDER_IMAGE_PRESET: c.VkExtent2D = .{ .width = 1920, .height = 1080 };

// Swapchain and Windows
pub const MAX_WINDOWS: u8 = 12;
