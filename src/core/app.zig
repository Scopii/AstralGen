const std = @import("std");
const vk = @import("vulkan");
const c = @import("../c.zig");

pub const App = struct {
    window: *c.GLFWwindow,
    extend: vk.Extent2D,
    window_width: c_int = undefined,
    window_height: c_int = undefined,

    pub fn init() !App {
        const extend = vk.Extent2D{ .width = 1280, .height = 720 };

        if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;

        if (c.glfwVulkanSupported() != c.GLFW_TRUE) {
            std.log.err("GLFW could not find libvulkan", .{});
            return error.NoVulkan;
        }

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

        const window = c.glfwCreateWindow(
            @intCast(extend.width),
            @intCast(extend.height),
            "AstralGen",
            null,
            null,
        ) orelse return error.WindowInitFailed;

        return App{
            .window = window,
            .extend = extend,
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
        c.glfwGetFramebufferSize(self.window, &self.window_width, &self.window_height);

        // Handle window minimization
        if (self.window_width == 0 or self.window_height == 0) {
            self.pollEvents();
            return false;
        }
        return true;
    }
};
