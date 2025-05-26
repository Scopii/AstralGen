const std = @import("std");
const vk = @import("vulkan");
const c = @import("../c.zig");

pub const App = struct {
    window: *c.GLFWwindow,
    extend: vk.Extent2D,

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

    pub fn pollEvens() void {
        c.glfwPollEvents();
    }
};
