const vk = @import("../../modules/vk.zig").c;
const Context = @import("Context.zig").Context;
const Cmd = @import("../types/base/Cmd.zig").Cmd;
const rc = @import("../../configs/renderConfig.zig");
const zgui = @import("zgui");
const std = @import("std");

const ig = @cImport(@cInclude("imgui_ctx.h"));

pub const ImGuiMan = struct {
    uiActive: bool = true,

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
            // subsequent windows share font atlas from context 0
            const atlas = ig.igui_get_font_atlas();
            const newCtx = ig.igui_create_context(atlas);
            ig.igui_copy_backend_to_context(newCtx); // copy SDL+Vulkan backend ptrs
            self.contexts[windowIdx] = newCtx;
        }
    }

    pub fn removeWindowContext(self: *ImGuiMan, windowIdx: u32) void {
        if (self.contexts[windowIdx]) |ctx| {
            ig.igui_destroy_context(ctx);
            self.contexts[windowIdx] = null;
        }
    }

    pub fn deinit(self: *ImGuiMan) void {
        if (!self.backendInitialized) return;
        // find and skip whichever index holds the bootstrap context
        const bootstrapCtx = self.contexts[self.bootstrapWindowId]; // need to store this
        for (self.contexts, 0..) |maybeCtx, i| {
            _ = i;
            if (maybeCtx) |ctx| {
                if (ctx == bootstrapCtx) continue; // zgui.deinit handles this one
                ig.igui_destroy_context(ctx);
            }
        }
        zgui.backend.deinit();
        zgui.deinit();
    }

    fn setContext(self: *ImGuiMan, windowIdx: u32) bool {
        const ctx = self.contexts[windowIdx] orelse return false;
        ig.igui_set_current_context(ctx);
        return true;
    }

    pub fn newFrame(self: *ImGuiMan, windowIdx: u32, width: u32, height: u32) void {
        if (!self.uiActive) return; // global toggle
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
