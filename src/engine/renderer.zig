const std = @import("std");
const c = @import("../c.zig");
const createDevice = @import("device.zig").createDevice;
const checkDeviceQueueFamilies = @import("device.zig").checkDeviceQueueFamilies;
const createSurface = @import("surface.zig").createSurface;
const Swapchain = @import("swapchain.zig").Swapchain;
const createPipeline = @import("pipeline.zig").createPipeline;
const createCmdPool = @import("command.zig").createCmdPool;
const createCmdBuffer = @import("command.zig").createCmdBuffer;
const recordCommandBuffer = @import("command.zig").recordCommandBuffer;
const createFence = @import("sync.zig").createFence;
const createSemaphore = @import("sync.zig").createSemaphore;

const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    initilized: bool = false,
    frameNumber: u32 = 0,
    stop_rendering: bool = false,

    instance: c.VkInstance,
    device: c.VkDevice,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,
    surface: c.VkSurfaceKHR,
    swapchain: Swapchain,
    pipeline: c.VkPipeline,
    cmdPool: c.VkCommandPool,
    cmdBuffer: c.VkCommandBuffer,
    imageRdySemaphore: c.VkSemaphore,
    renderDoneSemaphore: c.VkSemaphore,
    inFlightFence: c.VkFence,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: c.VkExtent2D) !Renderer {
        const instance = try createInstance(alloc);
        const surface = try createSurface(window, instance);
        const device_combo = try createDevice(alloc, instance, surface);
        // Get the queues
        var graphics_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device_combo.device, device_combo.queue_families.graphics, 0, &graphics_queue);
        var present_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device_combo.device, device_combo.queue_families.present, 0, &present_queue);

        const swapchain = try Swapchain.init(alloc, device_combo.device, device_combo.phys_device, surface, extent, device_combo.queue_families);
        const pipeline = try createPipeline(device_combo.device, swapchain.surfaceFormat.format);
        const cmdPool = try createCmdPool(device_combo.device, device_combo.queue_families.graphics);
        const cmdBuffer = try createCmdBuffer(device_combo.device, cmdPool);

        const imageRdySemaphore = try createSemaphore(device_combo.device);
        const renderDoneSemaphore = try createSemaphore(device_combo.device);
        const inFlightFence = try createFence(device_combo.device);

        return .{
            .alloc = alloc,
            .instance = instance,
            .surface = surface,
            .device = device_combo.device,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
            .swapchain = swapchain,
            .pipeline = pipeline,
            .cmdPool = cmdPool,
            .cmdBuffer = cmdBuffer,
            .imageRdySemaphore = imageRdySemaphore,
            .renderDoneSemaphore = renderDoneSemaphore,
            .inFlightFence = inFlightFence,
        };
    }

    pub fn draw(self: *Renderer) !void {
        _ = c.vkWaitForFences(self.device, 1, &self.inFlightFence, c.VK_TRUE, std.math.maxInt(u64));
        _ = c.vkResetFences(self.device, 1, &self.inFlightFence);

        var imageIndex: u32 = undefined;
        _ = c.vkAcquireNextImageKHR(self.device, self.swapchain.handle, std.math.maxInt(u64), self.imageRdySemaphore, null, &imageIndex);

        _ = c.vkResetCommandBuffer(self.cmdBuffer, 0);
        try recordCommandBuffer(self.cmdBuffer, self.swapchain.extent, self.swapchain.imageViews, self.pipeline, imageIndex, self.swapchain); // Pass imageIndex

        const wait_semaphores = [_]c.VkSemaphore{self.imageRdySemaphore};
        const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
        const signal_semaphores = [_]c.VkSemaphore{self.renderDoneSemaphore};

        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = wait_semaphores.len,
            .pWaitSemaphores = &wait_semaphores,
            .pWaitDstStageMask = &wait_stages,
            .commandBufferCount = 1,
            .pCommandBuffers = &self.cmdBuffer,
            .signalSemaphoreCount = signal_semaphores.len,
            .pSignalSemaphores = &signal_semaphores,
        };

        if (c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.inFlightFence) != c.VK_SUCCESS) {
            return error.FailedToSubmitDraw;
        }

        // Fixed present info - use signal_semaphores not wait_semaphores
        const swapchains = [_]c.VkSwapchainKHR{self.swapchain.handle};
        const image_indices = [_]u32{imageIndex};

        const presentInfo = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = signal_semaphores.len, // Wait for render to complete
            .pWaitSemaphores = &signal_semaphores, // Use signal semaphores here
            .swapchainCount = 1, // Missing field
            .pSwapchains = &swapchains, // Missing field
            .pImageIndices = &image_indices, // Missing field
            .pResults = null, // Missing field
        };

        _ = c.vkQueuePresentKHR(self.present_queue, &presentInfo);
    }

    pub fn deinit(self: *Renderer) void {
        c.vkDestroySemaphore(self.device, self.imageRdySemaphore, null);
        c.vkDestroySemaphore(self.device, self.renderDoneSemaphore, null);
        c.vkDestroyFence(self.device, self.inFlightFence, null);
        c.vkDestroyCommandPool(self.device, self.cmdPool, null);
        self.swapchain.deinit(self.device);
        c.vkDestroyPipeline(self.device, self.pipeline, null);
        c.vkDestroyDevice(self.device, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};

pub fn createInstance(alloc: Allocator) !c.VkInstance {
    // get required extensions
    var extension_count: u32 = 0;
    const required_extensions = c.SDL_Vulkan_GetInstanceExtensions(&extension_count); // VK_EXT_DEBUG_REPORT_EXTENSION_NAME

    var extensions = std.ArrayList([*c]const u8).init(alloc);
    defer extensions.deinit();
    for (0..extension_count) |i| {
        try extensions.append(required_extensions[i]);
    }

    try extensions.append("VK_EXT_debug_utils");
    try extensions.append("VK_EXT_debug_report");
    try extensions.append("VK_KHR_portability_enumeration");
    try extensions.append("VK_KHR_get_physical_device_properties2");
    std.debug.print("Extension Count {}\n", .{extension_count});

    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "AstralGen",
        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "AstralEngine",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_3,
    };

    // validation layer
    var layers = std.ArrayList([*c]const u8).init(alloc);
    defer layers.deinit();

    try layers.append("VK_LAYER_KHRONOS_validation");
    try layers.append("VK_LAYER_KHRONOS_synchronization2");

    const instance_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pApplicationInfo = &app_info,
        .enabledLayerCount = @intCast(layers.items.len),
        .ppEnabledLayerNames = layers.items.ptr,
        .enabledExtensionCount = @intCast(extensions.items.len),
        .ppEnabledExtensionNames = extensions.items.ptr,
    };

    var instance: c.VkInstance = undefined;
    const result = c.vkCreateInstance(&instance_info, null, &instance);
    if (result != c.VK_SUCCESS) {
        std.log.err("Unable to create Vulkan instance ! Reason {d}\n", .{result});
        return error.VkInstance;
    }

    return instance;
}
