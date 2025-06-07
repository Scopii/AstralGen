const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;
const getVkVal = @import("error.zig").getVkVal;

pub const QueueFamilies = struct {
    graphics: u32,
    present: u32,
};

pub const Device = struct {
    gpu: c.VkPhysicalDevice,
    gpi: c.VkDevice,
    graphicsQ: c.VkQueue,
    presentQ: c.VkQueue,
    families: QueueFamilies,

    pub fn init(alloc: Allocator, instance: c.VkInstance, surface: c.VkSurfaceKHR) !Device {
        const gpu = try pickGPU(alloc, instance);
        const families = try checkGPUfamilies(alloc, surface, gpu);
        const gpi = try createGPI(alloc, gpu, families);

        var graphicsQ: c.VkQueue = undefined;
        c.vkGetDeviceQueue(gpi, families.graphics, 0, &graphicsQ);
        var presentQ: c.VkQueue = undefined;
        c.vkGetDeviceQueue(gpi, families.present, 0, &presentQ);

        return .{
            .gpu = gpu,
            .gpi = gpi,
            .graphicsQ = graphicsQ,
            .presentQ = presentQ,
            .families = families,
        };
    }
    pub fn deinit(self: *Device) void {
        c.vkDestroyDevice(self.gpi, null);
    }
};

pub fn pickGPU(alloc: Allocator, instance: c.VkInstance) !c.VkPhysicalDevice {
    var gpuCount: u32 = 0;
    try check(c.vkEnumeratePhysicalDevices(instance, &gpuCount, null), "Failed to enumerate GPUs");
    if (gpuCount == 0) return error.NoDevice;

    const gpus = try alloc.alloc(c.VkPhysicalDevice, gpuCount);
    defer alloc.free(gpus);
    try check(c.vkEnumeratePhysicalDevices(instance, &gpuCount, gpus.ptr), "Failed to get GPUs");

    var chosen: ?c.VkPhysicalDevice = null;
    for (gpus) |gpu| {
        if (checkGPU(gpu) and try checkGPUfeatures(alloc, gpu)) {
            chosen = gpu;
            break;
        }
    }
    if (chosen == null) {
        std.log.err("No suitable Vulkan GPUs found\n", .{});
        return error.NoDevice;
    }
    return chosen.?;
}

pub fn checkGPU(gpu: c.VkPhysicalDevice) bool {
    var properties: c.VkPhysicalDeviceProperties = undefined;
    c.vkGetPhysicalDeviceProperties(gpu, &properties);
    var features: c.VkPhysicalDeviceFeatures = undefined;
    c.vkGetPhysicalDeviceFeatures(gpu, &features);

    std.debug.print("Checking Device: {s}\n", .{properties.deviceName});
    if (properties.deviceType != c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
        std.debug.print("Device not a discrete GPU\n", .{});
        return false;
    }
    return true;
}

pub fn checkGPUfeatures(alloc: Allocator, gpu: c.VkPhysicalDevice) !bool {
    var extensions: u32 = 0;
    try check(c.vkEnumerateDeviceExtensionProperties(gpu, null, &extensions, null), "Failed to enumerate device extensions");

    const supported = try alloc.alloc(c.VkExtensionProperties, extensions);
    defer alloc.free(supported);
    try check(c.vkEnumerateDeviceExtensionProperties(gpu, null, &extensions, supported.ptr), "Failed to get device extensions");

    const required = [_][]const u8{ "VK_KHR_swapchain", "VK_KHR_synchronization2", "VK_KHR_dynamic_rendering" };
    var matched: u32 = 0;

    for (supported) |extension| {
        for (required) |reqExtension| {
            const ext_name: [*c]const u8 = @ptrCast(extension.extensionName[0..]);

            const match = std.mem.eql(u8, reqExtension, std.mem.span(ext_name));
            if (match) {
                matched += 1;
                break;
            }
        }
    }
    return matched == required.len;
}

pub fn checkGPUfamilies(alloc: Allocator, surface: c.VkSurfaceKHR, gpu: c.VkPhysicalDevice) !QueueFamilies {
    var familyCount: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, null);

    const families = try alloc.alloc(c.VkQueueFamilyProperties, familyCount);
    defer alloc.free(families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, families.ptr);

    var graphicsFamily: ?usize = null;
    var presentFamily: ?usize = null;

    for (families, 0..) |family, index| {
        if (family.queueCount > 0 and family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) graphicsFamily = index;

        var presentSupport: c.VkBool32 = c.VK_FALSE;
        try check(c.vkGetPhysicalDeviceSurfaceSupportKHR(gpu, @intCast(index), surface, &presentSupport), "No present support found!");

        if (family.queueCount > 0 and presentSupport == c.VK_TRUE) presentFamily = index;
        if (graphicsFamily != null and presentFamily != null) break;
    }
    const familyIndices = QueueFamilies{
        .graphics = @intCast(graphicsFamily.?),
        .present = @intCast(presentFamily.?),
    };
    return familyIndices;
}

pub fn createGPI(alloc: Allocator, gpu: c.VkPhysicalDevice, families: QueueFamilies) !c.VkDevice {
    var priority: f32 = 1.0;
    var queueInfos = std.ArrayList(c.VkDeviceQueueCreateInfo).init(alloc);
    defer queueInfos.deinit();

    const graphicsInf = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = families.graphics,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    };
    try queueInfos.append(graphicsInf);

    if (families.graphics != families.present) {
        const presentInf = c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = families.present,
            .queueCount = 1,
            .pQueuePriorities = &priority,
        };
        try queueInfos.append(presentInf);
    }

    var features: c.VkPhysicalDeviceFeatures = undefined;
    c.vkGetPhysicalDeviceFeatures(gpu, &features);

    const features_vulkan12 = c.VkPhysicalDeviceVulkan12Features{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .bufferDeviceAddress = c.VK_TRUE,
        .descriptorIndexing = c.VK_TRUE,
        .timelineSemaphore = c.VK_TRUE,
    };

    const features13_to_enable = c.VkPhysicalDeviceVulkan13Features{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .dynamicRendering = c.VK_TRUE,
        .synchronization2 = c.VK_TRUE,
        .pNext = @constCast(@ptrCast(&features_vulkan12)),
    };
    // Enable required gpu extensions
    const gpuExtensions = [_][*c]const u8{
        "VK_KHR_swapchain",
    };

    const createInfo = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &features13_to_enable,
        .pQueueCreateInfos = queueInfos.items.ptr,
        .queueCreateInfoCount = @intCast(queueInfos.items.len),
        .pEnabledFeatures = &features,
        .enabledExtensionCount = gpuExtensions.len,
        .ppEnabledExtensionNames = &gpuExtensions,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
    };

    var gpi: c.VkDevice = undefined;
    try check(c.vkCreateDevice(gpu, &createInfo, null, &gpi), "Unable to create Vulkan device!");
    return gpi;
}
