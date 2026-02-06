const vk = @import("../../modules/vk.zig").c;
const Context = @import("Context.zig").Context;
const Cmd = @import("../types/base/Cmd.zig").Cmd;
const rc = @import("../../configs/renderConfig.zig");
const zgui = @import("zgui");
const std = @import("std");

pub const ImGuiMan = struct {
    pool: vk.VkDescriptorPool,

    pub fn init(context: *const Context, sdl_window: *vk.SDL_Window) !ImGuiMan {
        // 1. Init zgui logic
        zgui.init(std.heap.c_allocator);

        // 2. Create a Descriptor Pool (Required by ImGui even for bindless engines)
        const pool_sizes = [_]vk.VkDescriptorPoolSize{
            .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 1000 },
        };
        const pool_info = vk.VkDescriptorPoolCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .flags = vk.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
            .maxSets = 1000,
            .poolSizeCount = 1,
            .pPoolSizes = &pool_sizes,
        };
        var pool: vk.VkDescriptorPool = undefined;
        _ = vk.vkCreateDescriptorPool(context.gpi, &pool_info, null, &pool);

        // 3. Init SDL3 and Vulkan Backends via C
        _ = vk.bridge_ImGui_ImplSDL3_InitForVulkan(sdl_window);

        var info = std.mem.zeroInit(vk.ZigImGuiInitInfo, .{
            .Instance = context.instance,
            .PhysicalDevice = context.gpu,
            .Device = context.gpi,
            .QueueFamily = context.families.graphics,
            .Queue = context.graphicsQ.handle,
            .DescriptorPool = pool,
            .MinImageCount = rc.DESIRED_SWAPCHAIN_IMAGES,
            .ImageCount = rc.DESIRED_SWAPCHAIN_IMAGES,
            .ColorAttachmentFormat = rc.TEX_COLOR_FORMAT,
            .DepthAttachmentFormat = rc.TEX_DEPTH_FORMAT,
        });

        _ = vk.bridge_ImGui_ImplVulkan_Init(&info);

        return .{ .pool = pool };
    }

    pub fn deinit(self: *ImGuiMan, gpi: vk.VkDevice) void {
        _ = vk.bridge_ImGui_ImplVulkan_Shutdown();
        _ = vk.bridge_ImGui_ImplSDL3_Shutdown();
        zgui.deinit();
        vk.vkDestroyDescriptorPool(gpi, self.pool, null);
    }

    pub fn newFrame(_: *ImGuiMan) void {
        _ = vk.bridge_ImGui_ImplVulkan_NewFrame();
        _ = vk.bridge_ImGui_ImplSDL3_NewFrame();
        zgui.newFrame();
    }

    pub fn render(_: *ImGuiMan, cmd: *const Cmd) void {
        zgui.render(); // This prepares zgui's internal draw data
        vk.bridge_ImGui_ImplVulkan_RenderDrawData(cmd.handle);
    }
};
