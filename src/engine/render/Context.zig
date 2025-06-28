const std = @import("std");
const c = @import("../../c.zig");
const check = @import("../error.zig").check;
const Allocator = std.mem.Allocator;

pub const QueueFamilies = struct {
    graphics: u32,
    present: u32,
};

pub const Context = struct {
    alloc: Allocator,
    instance: c.VkInstance,
    surfaceFormat: c.VkSurfaceFormatKHR,
    gpu: c.VkPhysicalDevice,
    families: QueueFamilies,
    gpi: c.VkDevice,
    graphicsQ: c.VkQueue,
    presentQ: c.VkQueue,

    pub fn init(alloc: Allocator, instance: c.VkInstance, surface: c.VkSurfaceKHR) !Context {
        const gpu = try pickGPU(alloc, instance);
        const surfaceFormat = try pickSurfaceFormat(alloc, gpu, surface);
        const families = try checkGPUfamilies(alloc, surface, gpu);
        const gpi = try createGPI(alloc, gpu, families);

        var graphicsQ: c.VkQueue = undefined;
        c.vkGetDeviceQueue(gpi, families.graphics, 0, &graphicsQ);
        var presentQ: c.VkQueue = undefined;
        c.vkGetDeviceQueue(gpi, families.present, 0, &presentQ);

        return .{
            .alloc = alloc,
            .instance = instance,
            .surfaceFormat = surfaceFormat,
            .gpu = gpu,
            .families = families,
            .gpi = gpi,
            .graphicsQ = graphicsQ,
            .presentQ = presentQ,
        };
    }

    pub fn deinit(self: *const Context) void {
        c.vkDestroyDevice(self.gpi, null);
        c.vkDestroyInstance(self.instance, null);
    }

    fn pickPresentMode(self: *const Context) !c.VkPresentModeKHR {
        const gpu = self.gpu;
        const surface = self.surface;
        var modeCount: u32 = 0;
        try check(c.vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &modeCount, null), "Failed to get present mode count");

        if (modeCount == 0) return c.VK_PRESENT_MODE_FIFO_KHR; // FIFO is always supported

        const modes = try self.alloc.alloc(c.VkPresentModeKHR, modeCount);
        defer self.alloc.free(modes);

        try check(c.vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &modeCount, modes.ptr), "Failed to get present modes");

        // Prefer mailbox (triple buffering), then immediate, fallback to FIFO
        for (modes) |mode| {
            if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) return mode;
        }
        for (modes) |mode| {
            if (mode == c.VK_PRESENT_MODE_IMMEDIATE_KHR) return mode;
        }
        return c.VK_PRESENT_MODE_FIFO_KHR;
    }
};

pub fn getSurfaceCaps(gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkSurfaceCapabilitiesKHR {
    var caps: c.VkSurfaceCapabilitiesKHR = undefined;
    try check(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &caps), "Failed to get surface capabilities");
    return caps;
}

pub fn createSurface(window: *c.SDL_Window, instance: c.VkInstance) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    if (c.SDL_Vulkan_CreateSurface(window, @ptrCast(instance), null, @ptrCast(&surface)) == false) {
        std.log.err("Unable to create Vulkan surface: {s}\n", .{c.SDL_GetError()});
        return error.VkSurface;
    }
    return surface;
}

pub fn pickSurfaceFormat(alloc: Allocator, gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkSurfaceFormatKHR {
    var formatCount: u32 = 0;
    try check(c.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, null), "Failed to get format count");

    if (formatCount == 0) return error.NoSurfaceFormats;

    const formats = try alloc.alloc(c.VkSurfaceFormatKHR, formatCount);
    defer alloc.free(formats);

    try check(c.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, formats.ptr), "Failed to get surface formats");

    // Return preferred format if available, otherwise first one
    if (formats.len == 1 and formats[0].format == c.VK_FORMAT_UNDEFINED) {
        return c.VkSurfaceFormatKHR{ .format = c.VK_FORMAT_B8G8R8A8_UNORM, .colorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR };
    }

    for (formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_UNORM and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return format;
        }
    }
    return formats[0];
}

pub fn createInstance(alloc: Allocator, debugToggle: bool) !c.VkInstance {
    // Create Arrays
    var extensions = std.ArrayList([*c]const u8).init(alloc);
    defer extensions.deinit();
    var layers = std.ArrayList([*c]const u8).init(alloc);
    defer layers.deinit();

    // get required extensions
    var extCount: u32 = 0;
    const reqExtensions = c.SDL_Vulkan_GetInstanceExtensions(&extCount); // VK_EXT_DEBUG_REPORT_EXTENSION_NAME
    for (0..extCount) |i| {
        try extensions.append(reqExtensions[i]);
    }

    if (debugToggle) {
        try extensions.append("VK_EXT_debug_utils");
        try layers.append("VK_LAYER_KHRONOS_validation");
        try layers.append("VK_LAYER_KHRONOS_synchronization2");
    }

    //try extensions.append("VK_KHR_portability_enumeration");
    try extensions.append("VK_KHR_get_physical_device_properties2");
    std.debug.print("Instance Extensions {}\n", .{extensions.items.len});

    const appInf = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "AstralGen",
        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "AstralEngine",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_3,
    };

    const instanceInf = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pApplicationInfo = &appInf,
        .enabledLayerCount = @intCast(layers.items.len),
        .ppEnabledLayerNames = layers.items.ptr,
        .enabledExtensionCount = @intCast(extensions.items.len),
        .ppEnabledExtensionNames = extensions.items.ptr,
    };

    var instance: c.VkInstance = undefined;
    try check(c.vkCreateInstance(&instanceInf, null, &instance), "Unable to create Vulkan instance!");

    return instance;
}

// DEVICE //

fn pickGPU(alloc: Allocator, instance: c.VkInstance) !c.VkPhysicalDevice {
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
        std.log.err("No suitable GPUs found\n", .{});
        return error.NoDevice;
    }
    return chosen.?;
}

pub fn checkGPU(gpu: c.VkPhysicalDevice) bool {
    var properties: c.VkPhysicalDeviceProperties = undefined;
    c.vkGetPhysicalDeviceProperties(gpu, &properties);
    var features: c.VkPhysicalDeviceFeatures = undefined;
    c.vkGetPhysicalDeviceFeatures(gpu, &features);

    std.debug.print("Testing: {s}\n", .{properties.deviceName});
    if (properties.deviceType != c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
        std.debug.print("Device not discrete GPU\n", .{});
        return false;
    }
    return true;
}

fn checkGPUfeatures(alloc: Allocator, gpu: c.VkPhysicalDevice) !bool {
    var extensions: u32 = 0;
    try check(c.vkEnumerateDeviceExtensionProperties(gpu, null, &extensions, null), "Failed to enumerate device extensions");

    const supported = try alloc.alloc(c.VkExtensionProperties, extensions);
    defer alloc.free(supported);
    try check(c.vkEnumerateDeviceExtensionProperties(gpu, null, &extensions, supported.ptr), "Failed to get device extensions");

    const required = [_][]const u8{"VK_KHR_swapchain"};
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

fn findFamily(families: []const c.VkQueueFamilyProperties) ?u32 {
    for (families, 0..) |family, i| {
        if (family.queueCount > 0 and (family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) and (family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0)) return @intCast(i);
    }
    return null;
}

fn findPresentFamily(families: []const c.VkQueueFamilyProperties, surface: c.VkSurfaceKHR, gpu: c.VkPhysicalDevice) !?u32 {
    for (families, 0..) |family, i| {
        var presentSupport: c.VkBool32 = c.VK_FALSE;
        try check(c.vkGetPhysicalDeviceSurfaceSupportKHR(gpu, @intCast(i), surface, &presentSupport), "Failed to get present support");
        if (presentSupport == c.VK_TRUE and family.queueCount != 0) return @intCast(i);
    }
    return null;
}

fn checkGPUfamilies(alloc: Allocator, surface: c.VkSurfaceKHR, gpu: c.VkPhysicalDevice) !QueueFamilies {
    var familyCount: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, null);

    const families = try alloc.alloc(c.VkQueueFamilyProperties, familyCount);
    defer alloc.free(families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, families.ptr);

    // Check family types
    const graphics = findFamily(families) orelse return error.NoGraphicsFamily;
    const present = try findPresentFamily(families, surface, gpu) orelse return error.NoPresentFamily;

    return QueueFamilies{
        .graphics = graphics,
        .present = present,
    };
}

fn createGPI(alloc: Allocator, gpu: c.VkPhysicalDevice, families: QueueFamilies) !c.VkDevice {
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

    var mesh_shader_features = c.VkPhysicalDeviceMeshShaderFeaturesEXT{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT,
        .taskShader = c.VK_TRUE,
        .meshShader = c.VK_TRUE,
    };

    const features_vulkan12 = c.VkPhysicalDeviceVulkan12Features{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .bufferDeviceAddress = c.VK_TRUE,
        .descriptorIndexing = c.VK_TRUE,
        .timelineSemaphore = c.VK_TRUE,
        .pNext = &mesh_shader_features,
    };

    const features13_to_enable = c.VkPhysicalDeviceVulkan13Features{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .dynamicRendering = c.VK_TRUE,
        .synchronization2 = c.VK_TRUE,
        .maintenance4 = c.VK_TRUE,
        .pNext = @constCast(@ptrCast(&features_vulkan12)),
    };

    const gpuExtensions = [_][*c]const u8{ "VK_KHR_swapchain", "VK_EXT_mesh_shader" };

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
    std.debug.print("Queues: {}\n", .{queueInfos.items.len});
    var gpi: c.VkDevice = undefined;
    try check(c.vkCreateDevice(gpu, &createInfo, null, &gpi), "Unable to create Vulkan device!");

    // Import Mesh Shader Draw Function
    const generic_fn_ptr = c.vkGetDeviceProcAddr(gpi, "vkCmdDrawMeshTasksEXT");

    if (generic_fn_ptr) |p| {
        c.pfn_vkCmdDrawMeshTasksEXT = @ptrCast(p);
    } else {
        c.pfn_vkCmdDrawMeshTasksEXT = null;
    }
    if (c.pfn_vkCmdDrawMeshTasksEXT == null) {
        std.log.err("FATAL: Could not load the vkCmdDrawMeshTasksEXT function pointer!\n", .{});
        return error.MissingVulkanFunction;
    }
    return gpi;
}
