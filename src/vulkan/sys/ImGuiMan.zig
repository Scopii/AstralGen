const vk = @import("../../modules/vk.zig").c;
const Context = @import("Context.zig").Context;
const Cmd = @import("../types/base/Cmd.zig").Cmd;
const rc = @import("../../configs/renderConfig.zig");
const zgui = @import("zgui");
const std = @import("std");

pub const ImGuiMan = struct {
    uiActive: bool = true,

    pub fn init(context: *const Context, sdl_window: *vk.SDL_Window) !ImGuiMan {
        zgui.init(std.heap.c_allocator);

        const loaded = zgui.backend.loadFunctions(
            vk.VK_API_VERSION_1_3,
            vulkanGetProcAddr,
            context.instance,
        );
        if (!loaded) {
            return error.VulkanFunctionLoadingFailed;
        }

        const swapchain_format = vk.VK_FORMAT_B8G8R8A8_UNORM;

        zgui.backend.init(
            .{
                .api_version = vk.VK_API_VERSION_1_3,
                .instance = context.instance,
                .physical_device = context.gpu,
                .device = context.gpi,
                .queue_family = context.families.graphics,
                .queue = context.graphicsQ.handle,
                .descriptor_pool = null,
                .min_image_count = rc.DESIRED_SWAPCHAIN_IMAGES,
                .image_count = rc.DESIRED_SWAPCHAIN_IMAGES,
                .msaa_samples = 0,
                .descriptor_pool_size = 1000,
                .use_dynamic_rendering = true,
                .render_pass = null,
                .pipeline_rendering_create_info = .{
                    .s_type = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
                    .view_mask = 0, //vk.VK_SAMPLE_COUNT_1_BIT
                    .color_attachment_count = 1,
                    .p_color_attachment_formats = @ptrCast(&swapchain_format),
                    .depth_attachment_format = vk.VK_FORMAT_UNDEFINED,
                    .stencil_attachment_format = vk.VK_FORMAT_UNDEFINED,
                },
            },
            sdl_window,
        );
        return .{};
    }

    pub fn deinit(_: *ImGuiMan, _: vk.VkDevice) void {
        zgui.backend.deinit();
        zgui.deinit();
    }

    pub fn drawUi(self: *ImGuiMan) void {
        if (self.uiActive == true) {
            zgui.showDemoWindow(null);
        }
    }

    pub fn newFrame(self: *ImGuiMan) void {
        if (self.uiActive == true) {
            zgui.backend.newFrame(1920, 1080); // Window Dimensions
        }
    }

    pub fn toogleUiMode(self: *ImGuiMan) void {
        if (self.uiActive == true) self.uiActive = false else self.uiActive = true;
    }

    pub fn render(self: *ImGuiMan, cmd: *const Cmd) void {
        if (self.uiActive == true) {
            zgui.render();
            zgui.backend.render(cmd.handle);
        }
    }
};

fn vulkanGetProcAddr(function_name: [*:0]const u8, user_data: ?*anyopaque) callconv(.c) ?*anyopaque {
    const instance = @as(vk.VkInstance, @ptrCast(user_data));
    const result = vk.vkGetInstanceProcAddr(instance, function_name);
    return @ptrCast(@constCast(result));
}
