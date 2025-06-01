const std = @import("std");
const c = @import("../c.zig");
const createGPinfo = @import("device.zig").createGPinfo;
const createSurface = @import("surface.zig").createSurface;
const Swapchain = @import("swapchain.zig").Swapchain;
const createPipeline = @import("pipeline.zig").createPipeline;
const createCmdPool = @import("command.zig").createCmdPool;
const createCmdBuffer = @import("command.zig").createCmdBuffer;
const recordCmdBuffer = @import("command.zig").recordCmdBuffer;
const createFence = @import("sync.zig").createFence;
const createSemaphore = @import("sync.zig").createSemaphore;
const check = @import("error.zig").check;

const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    initilized: bool = false,
    frameNumber: u32 = 0,
    stop_rendering: bool = false,

    instance: c.VkInstance,
    gpi: c.VkDevice,
    gQueue: c.VkQueue,
    pQueue: c.VkQueue,
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
        const deviceInfo = try createGPinfo(alloc, instance, surface);
        const gpi = deviceInfo.gpi;
        const gpu = deviceInfo.gpu;
        // Get the queues
        var gQueue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(gpi, deviceInfo.families.graphics, 0, &gQueue);
        var pQueue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(gpi, deviceInfo.families.present, 0, &pQueue);

        const swapchain = try Swapchain.init(alloc, gpi, gpu, surface, extent, deviceInfo.families);
        const pipeline = try createPipeline(gpi, swapchain.surfaceFormat.format);
        const cmdPool = try createCmdPool(gpi, deviceInfo.families.graphics);
        const cmdBuffer = try createCmdBuffer(gpi, cmdPool);

        const imageRdySemaphore = try createSemaphore(gpi);
        const renderDoneSemaphore = try createSemaphore(gpi);
        const inFlightFence = try createFence(gpi);

        return .{
            .alloc = alloc,
            .instance = instance,
            .surface = surface,
            .gpi = gpi,
            .gQueue = gQueue,
            .pQueue = pQueue,
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
        //try check(, );

        try check(c.vkWaitForFences(self.gpi, 1, &self.inFlightFence, c.VK_TRUE, std.math.maxInt(u64)), "Could not wait for inFlightFence");
        try check(c.vkResetFences(self.gpi, 1, &self.inFlightFence), "Could not reset inFlightFence");

        var imageIndex: u32 = 0;
        try check(c.vkAcquireNextImageKHR(self.gpi, self.swapchain.handle, std.math.maxInt(u64), self.imageRdySemaphore, null, &imageIndex), "could not acquire Next Image");
        try check(c.vkResetCommandBuffer(self.cmdBuffer, 0), "Could not reset cmdBuffer");
        try recordCmdBuffer(self.cmdBuffer, self.swapchain.extent, self.swapchain.imageViews, self.pipeline, imageIndex, self.swapchain); // Pass imageIndex

        const waitSemaphores = [_]c.VkSemaphore{self.imageRdySemaphore};
        const waitStages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
        const signalSemaphores = [_]c.VkSemaphore{self.renderDoneSemaphore};

        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = waitSemaphores.len,
            .pWaitSemaphores = &waitSemaphores,
            .pWaitDstStageMask = &waitStages,
            .commandBufferCount = 1,
            .pCommandBuffers = &self.cmdBuffer,
            .signalSemaphoreCount = signalSemaphores.len,
            .pSignalSemaphores = &signalSemaphores,
        };

        try check(c.vkQueueSubmit(self.gQueue, 1, &submit_info, self.inFlightFence), "Failed to submit to Queue");

        const swapchains = [_]c.VkSwapchainKHR{self.swapchain.handle};
        const imageIndices = [_]u32{imageIndex};

        const presentInfo = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = signalSemaphores.len,
            .pWaitSemaphores = &signalSemaphores,
            .swapchainCount = 1,
            .pSwapchains = &swapchains,
            .pImageIndices = &imageIndices,
            .pResults = null,
        };

        try check(c.vkQueuePresentKHR(self.pQueue, &presentInfo), "could not present Queue");
    }

    pub fn deinit(self: *Renderer) void {
        c.vkDestroySemaphore(self.gpi, self.imageRdySemaphore, null);
        c.vkDestroySemaphore(self.gpi, self.renderDoneSemaphore, null);
        c.vkDestroyFence(self.gpi, self.inFlightFence, null);
        c.vkDestroyCommandPool(self.gpi, self.cmdPool, null);
        self.swapchain.deinit(self.gpi);
        c.vkDestroyPipeline(self.gpi, self.pipeline, null);
        c.vkDestroyDevice(self.gpi, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};

pub fn createInstance(alloc: Allocator) !c.VkInstance {
    // get required extensions
    var extCount: u32 = 0;
    const reqExtensions = c.SDL_Vulkan_GetInstanceExtensions(&extCount); // VK_EXT_DEBUG_REPORT_EXTENSION_NAME

    var extensions = std.ArrayList([*c]const u8).init(alloc);
    defer extensions.deinit();

    for (0..extCount) |i| {
        try extensions.append(reqExtensions[i]);
    }

    try extensions.append("VK_EXT_debug_utils");
    try extensions.append("VK_EXT_debug_report");
    try extensions.append("VK_KHR_portability_enumeration");
    try extensions.append("VK_KHR_get_physical_device_properties2");
    std.debug.print("Extension Count {}\n", .{extCount});

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

    const instanceInfo = c.VkInstanceCreateInfo{
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
    try check(c.vkCreateInstance(&instanceInfo, null, &instance), "Unable to create Vulkan instance!");

    return instance;
}
