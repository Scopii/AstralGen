const vk = @import("../../.modules/vk.zig").c;
const Context = @import("Context.zig").Context;
const Cmd = @import("../types/base/Cmd.zig").Cmd;
const rc = @import("../../.configs/renderConfig.zig");
const zgui = @import("zgui");
const std = @import("std");

const ig = @cImport(@cInclude("imgui_ctx.h"));

pub const ImGuiMan = struct {
    uiActive: bool = false,

    instance: vk.VkInstance,
    gpu: vk.VkPhysicalDevice,
    gpi: vk.VkDevice,
    graphicsFamily: u32,
    graphicsQueue: vk.VkQueue,

    contexts: [rc.MAX_WINDOWS + 32]?*ig.ImGuiContext = .{null} ** (rc.MAX_WINDOWS + 32),
    backendInitialized: bool = false,

    bootstrapWindowId: u32 = 0,

    pub fn init(context: *const Context) ImGuiMan { // no zgui calls yet
        return .{
            .instance = context.instance,
            .gpu = context.gpu,
            .gpi = context.gpi,
            .graphicsFamily = context.graphicsQ.family,
            .graphicsQueue = context.graphicsQ.handle,
        };
    }

    pub fn addWindowContext(self: *ImGuiMan, windowIdx: u32, sdlWindow: *vk.SDL_Window) !void {
        if (!self.backendInitialized) {
            // first window registration bootstraps the whole backend
            zgui.init(std.heap.c_allocator);
            const loaded = zgui.backend.loadFunctions(vk.VK_API_VERSION_1_3, vulkanGetProcAddr, self.instance);
            if (!loaded) return error.VulkanFunctionLoadingFailed;

            const swapchainFormat = vk.VK_FORMAT_B8G8R8A8_UNORM;
            zgui.backend.init(.{
                .api_version = vk.VK_API_VERSION_1_3,
                .instance = self.instance,
                .physical_device = self.gpu,
                .device = self.gpi,
                .queue_family = self.graphicsFamily,
                .queue = self.graphicsQueue,
                .descriptor_pool = null,
                .min_image_count = rc.DESIRED_SWAPCHAIN_IMAGES,
                .image_count = rc.DESIRED_SWAPCHAIN_IMAGES,
                .msaa_samples = 0,
                .descriptor_pool_size = 1000,
                .use_dynamic_rendering = true,
                .render_pass = null,
                .pipeline_rendering_create_info = .{
                    .s_type = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
                    .view_mask = 0,
                    .color_attachment_count = 1,
                    .p_color_attachment_formats = @ptrCast(&swapchainFormat),
                    .depth_attachment_format = vk.VK_FORMAT_UNDEFINED,
                    .stencil_attachment_format = vk.VK_FORMAT_UNDEFINED,
                },
            }, sdlWindow);

            // capture the context zgui.init created
            self.contexts[windowIdx] = ig.igui_get_current_context();
            self.backendInitialized = true;
            self.bootstrapWindowId = windowIdx;
        } else {
            const newCtx = ig.igui_create_context(null); // own atlas
            ig.igui_set_current_context(newCtx);

            const swapchainFormat = vk.VK_FORMAT_B8G8R8A8_UNORM;
            zgui.backend.init(.{ // full independent backend init for this context
                .api_version = vk.VK_API_VERSION_1_3,
                .instance = self.instance,
                .physical_device = self.gpu,
                .device = self.gpi,
                .queue_family = self.graphicsFamily,
                .queue = self.graphicsQueue,
                .descriptor_pool = null,
                .min_image_count = rc.DESIRED_SWAPCHAIN_IMAGES,
                .image_count = rc.DESIRED_SWAPCHAIN_IMAGES,
                .msaa_samples = 0,
                .descriptor_pool_size = 1000,
                .use_dynamic_rendering = true,
                .render_pass = null,
                .pipeline_rendering_create_info = .{
                    .s_type = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
                    .view_mask = 0,
                    .color_attachment_count = 1,
                    .p_color_attachment_formats = @ptrCast(&swapchainFormat),
                    .depth_attachment_format = vk.VK_FORMAT_UNDEFINED,
                    .stencil_attachment_format = vk.VK_FORMAT_UNDEFINED,
                },
            }, sdlWindow);

            self.contexts[windowIdx] = newCtx;
            ig.igui_set_current_context(self.contexts[self.bootstrapWindowId].?); // restore

        }
    }

    // pub fn removeWindowContext(self: *ImGuiMan, windowIdx: u32) void {
    //     if (self.contexts[windowIdx]) |ctx| {
    //         ig.igui_destroy_context(ctx);
    //         self.contexts[windowIdx] = null;
    //     }
    // }

    pub fn removeWindowContext(self: *ImGuiMan, windowIdx: u32) void {
        if (self.contexts[windowIdx]) |ctx| {
            ig.igui_set_current_context(ctx);
            zgui.backend.deinit(); // must come before destroy
            ig.igui_destroy_context(ctx);
            self.contexts[windowIdx] = null;
            // restore active context to bootstrap if it still exists
            if (self.contexts[self.bootstrapWindowId]) |bootstrap| {
                ig.igui_set_current_context(bootstrap);
            }
        }
    }

    pub fn deinit(self: *ImGuiMan) void {
        if (!self.backendInitialized) return;
        const bootstrapCtx = self.contexts[self.bootstrapWindowId];

        for (self.contexts) |maybeCtx| { // non-bootstrap first
            if (maybeCtx) |ctx| {
                if (ctx == bootstrapCtx) continue;
                ig.igui_set_current_context(ctx);
                zgui.backend.deinit();
                ig.igui_destroy_context(ctx);
            }
        }
        ig.igui_set_current_context(bootstrapCtx.?);
        zgui.backend.deinit();
        zgui.deinit();
    }

    pub fn setContext(self: *ImGuiMan, windowIdx: u32) bool {
        const ctx = self.contexts[windowIdx] orelse return false;
        ig.igui_set_current_context(ctx);
        return true;
    }

    pub fn processEvent(self: *ImGuiMan, windowId: u32, event: anytype) void {
        if (!self.backendInitialized) return;
        if (!self.setContext(windowId)) return;
        _ = zgui.backend.processEvent(event);
    }

    pub fn newFrame(self: *ImGuiMan, windowIdx: u32, width: u32, height: u32) void {
        if (!self.uiActive) return;
        if (!self.setContext(windowIdx)) return;
        zgui.backend.newFrame(width, height);
    }

    pub fn toogleUiMode(self: *ImGuiMan) void {
        if (self.uiActive == true) self.uiActive = false else self.uiActive = true;
    }

    pub fn drawUi(self: *ImGuiMan, windowIdx: u32) void {
        if (!self.uiActive) return;
        if (!self.setContext(windowIdx)) return;
        zgui.showDemoWindow(null);
    }

    pub fn render(self: *ImGuiMan, windowIdx: u32, cmd: *const Cmd) void {
        if (!self.uiActive) return;
        if (!self.setContext(windowIdx)) return;
        zgui.render();
        zgui.backend.render(cmd.handle);
    }
};

fn vulkanGetProcAddr(function_name: [*:0]const u8, user_data: ?*anyopaque) callconv(.c) ?*anyopaque {
    const instance = @as(vk.VkInstance, @ptrCast(user_data));
    const result = vk.vkGetInstanceProcAddr(instance, function_name);
    return @ptrCast(@constCast(result));
}
