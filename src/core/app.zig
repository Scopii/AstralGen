const std = @import("std");
const vk = @import("vulkan");
const c = @import("../c.zig");

pub const App = struct {
    window: *c.GLFWwindow,
    extent: vk.Extent2D,
    curr_width: c_int = undefined,
    curr_height: c_int = undefined,

    pub fn init() !App {
        const extent = vk.Extent2D{ .width = 1280, .height = 720 };

        if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;

        if (c.glfwVulkanSupported() != c.GLFW_TRUE) {
            std.log.err("GLFW could not find libvulkan", .{});
            return error.NoVulkan;
        }

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

        const window = c.glfwCreateWindow(
            @intCast(extent.width),
            @intCast(extent.height),
            "AstralGen",
            null,
            null,
        ) orelse return error.WindowInitFailed;

        return App{
            .window = window,
            .extent = extent,
        };
    }

    pub fn deinit(self: *App) void {
        c.glfwDestroyWindow(self.window);
        c.glfwTerminate();
    }

    pub fn pollEvents(_: *App) void {
        c.glfwPollEvents();
    }

    pub fn shouldClose(self: *App) bool {
        return if (c.glfwWindowShouldClose(self.window) == c.GLFW_FALSE) true else false;
    }

    pub fn handle(self: *App) bool {
        c.glfwGetFramebufferSize(self.window, &self.curr_width, &self.curr_height);

        // Handle window minimization
        if (self.curr_width == 0 or self.curr_height == 0) {
            self.pollEvents();
            return false;
        }
        return true;
    }
};
