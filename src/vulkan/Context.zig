const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;
const config = @import("../config.zig");

pub const QueueFamilies = struct {
    graphics: u32,
    present: u32,
};

pub const Context = struct {
    alloc: Allocator,
    instance: c.VkInstance,
    gpu: c.VkPhysicalDevice,
    families: QueueFamilies,
    gpi: c.VkDevice,
    graphicsQ: c.VkQueue,
    presentQ: c.VkQueue,

    pub fn init(alloc: Allocator, instance: c.VkInstance) !Context {
        const gpu = try pickGPU(alloc, instance);
        const families = try checkGPUfamilies(alloc, gpu);
        const gpi = try createGPI(alloc, gpu, families);

        var graphicsQ: c.VkQueue = undefined;
        c.vkGetDeviceQueue(gpi, families.graphics, 0, &graphicsQ);
        var presentQ: c.VkQueue = undefined;
        c.vkGetDeviceQueue(gpi, families.present, 0, &presentQ);

        return .{
            .alloc = alloc,
            .instance = instance,
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
        for (modes) |mode| if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) return mode;
        for (modes) |mode| if (mode == c.VK_PRESENT_MODE_IMMEDIATE_KHR) return mode;
        return c.VK_PRESENT_MODE_FIFO_KHR;
    }
};

pub fn createInstance(alloc: Allocator) !c.VkInstance {
    var extensions = std.ArrayList([*c]const u8).init(alloc);
    defer extensions.deinit();
    var layers = std.ArrayList([*c]const u8).init(alloc);
    defer layers.deinit();

    // get required extensions
    var extCount: u32 = 0;
    const reqExtensions = c.SDL_Vulkan_GetInstanceExtensions(&extCount);
    for (0..extCount) |i| try extensions.append(reqExtensions[i]);

    if (config.DEBUG_MODE) {
        try extensions.append("VK_EXT_debug_utils");
        try layers.append("VK_LAYER_KHRONOS_validation");
        try layers.append("VK_LAYER_KHRONOS_synchronization2");
    }

    var extraValidationFeatures = switch (config.BEST_PRACTICES) {
        true => if (config.EXTRA_VALIDATION == true) [_]c.VkValidationFeatureEnableEXT{
            c.VK_VALIDATION_FEATURE_ENABLE_BEST_PRACTICES_EXT,
            c.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_EXT,
            c.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_RESERVE_BINDING_SLOT_EXT,
            c.VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT,
        } else [_]c.VkValidationFeatureEnableEXT{c.VK_VALIDATION_FEATURE_ENABLE_BEST_PRACTICES_EXT},
        false => [_]c.VkValidationFeatureEnableEXT{
            c.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_EXT,
            c.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_RESERVE_BINDING_SLOT_EXT,
            c.VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT,
        },
    };

    var extraValidationExtensions = c.VkValidationFeaturesEXT{
        .sType = c.VK_STRUCTURE_TYPE_VALIDATION_FEATURES_EXT,
        .pNext = null,
        .enabledValidationFeatureCount = extraValidationFeatures.len,
        .pEnabledValidationFeatures = &extraValidationFeatures,
        .disabledValidationFeatureCount = 0,
        .pDisabledValidationFeatures = null,
    };

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
        .pNext = if (config.EXTRA_VALIDATION or config.BEST_PRACTICES) @ptrCast(&extraValidationExtensions) else null,
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

// Not in use because using the same Family because most Graphics Queues support Presentation and this avoids creating a Surface for setup
fn findPresentFamily(families: []const c.VkQueueFamilyProperties, gpu: c.VkPhysicalDevice) !?u32 {
    for (families, 0..) |family, i| {
        var presentSupport: c.VkBool32 = c.VK_FALSE;
        try check(c.vkGetPhysicalDeviceSurfaceSupportKHR(gpu, @intCast(i), null, &presentSupport), "Failed to get present support");
        if (presentSupport == c.VK_TRUE and family.queueCount != 0) return @intCast(i);
    }
    return null;
}

fn checkGPUfamilies(alloc: Allocator, gpu: c.VkPhysicalDevice) !QueueFamilies {
    var familyCount: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, null);

    const families = try alloc.alloc(c.VkQueueFamilyProperties, familyCount);
    defer alloc.free(families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, families.ptr);

    const graphics = findFamily(families) orelse return error.NoGraphicsFamily;
    // Currently using the same Family because most Graphics Queues support Presentation and this avoids creating a Surface for setup
    const present = graphics; // try findPresentFamily(families, surface, gpu) orelse return error.NoPresentFamily;

    return QueueFamilies{ .graphics = graphics, .present = present };
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

    var extended_dynamic_state3_features = c.VkPhysicalDeviceExtendedDynamicState3FeaturesEXT{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT,
        .pNext = null,
        .extendedDynamicState3ColorBlendEnable = c.VK_TRUE,
        .extendedDynamicState3ColorWriteMask = c.VK_TRUE,
    };

    var extended_dynamic_state2_features = c.VkPhysicalDeviceExtendedDynamicState2FeaturesEXT{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT,
        .pNext = &extended_dynamic_state3_features,
        .extendedDynamicState2 = c.VK_TRUE,
        .extendedDynamicState2LogicOp = c.VK_TRUE,
        .extendedDynamicState2PatchControlPoints = c.VK_TRUE,
    };

    var extended_dynamic_state_features = c.VkPhysicalDeviceExtendedDynamicStateFeaturesEXT{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
        .pNext = &extended_dynamic_state2_features,
        .extendedDynamicState = c.VK_TRUE,
    };

    var shader_object_features = c.VkPhysicalDeviceShaderObjectFeaturesEXT{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT,
        .pNext = &extended_dynamic_state_features,
        .shaderObject = c.VK_TRUE,
    };

    var mesh_shader_features = c.VkPhysicalDeviceMeshShaderFeaturesEXT{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT,
        .pNext = &shader_object_features,
        .taskShader = c.VK_TRUE,
        .meshShader = c.VK_TRUE,
    };

    var descriptor_buffer_features = c.VkPhysicalDeviceDescriptorBufferFeaturesEXT{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT,
        .pNext = &mesh_shader_features,
        .descriptorBuffer = c.VK_TRUE,
    };

    const features_vulkan12 = c.VkPhysicalDeviceVulkan12Features{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .bufferDeviceAddress = c.VK_TRUE,
        .descriptorIndexing = c.VK_TRUE,
        .timelineSemaphore = c.VK_TRUE,
        .pNext = &descriptor_buffer_features,
    };

    const features13_to_enable = c.VkPhysicalDeviceVulkan13Features{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .dynamicRendering = c.VK_TRUE,
        .synchronization2 = c.VK_TRUE,
        .maintenance4 = c.VK_TRUE,
        .pNext = @constCast(@ptrCast(&features_vulkan12)),
    };

    const gpuExtensions = [_][*c]const u8{
        "VK_KHR_swapchain",
        "VK_EXT_mesh_shader",
        "VK_EXT_descriptor_buffer",
        "VK_EXT_shader_object",
        "VK_EXT_extended_dynamic_state",
        "VK_EXT_extended_dynamic_state2",
        "VK_EXT_extended_dynamic_state3",
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
    std.debug.print("Queues: {}\n", .{queueInfos.items.len});
    var gpi: c.VkDevice = undefined;
    try check(c.vkCreateDevice(gpu, &createInfo, null, &gpi), "Unable to create Vulkan device!");

    // Mesh Shader Draw Function
    loadVkProc(gpi, &c.pfn_vkCmdDrawMeshTasksEXT, "vkCmdDrawMeshTasksEXT");
    // additional dynamic state function pointers
    loadVkProc(gpi, &c.pfn_vkCmdSetRasterizerDiscardEnable, "vkCmdSetRasterizerDiscardEnable");
    loadVkProc(gpi, &c.pfn_vkCmdSetCullMode, "vkCmdSetCullMode");
    loadVkProc(gpi, &c.pfn_vkCmdSetFrontFace, "vkCmdSetFrontFace");
    loadVkProc(gpi, &c.pfn_vkCmdSetDepthTestEnable, "vkCmdSetDepthTestEnable");
    loadVkProc(gpi, &c.pfn_vkCmdSetDepthWriteEnable, "vkCmdSetDepthWriteEnable");
    loadVkProc(gpi, &c.pfn_vkCmdSetDepthBoundsTestEnable, "vkCmdSetDepthBoundsTestEnable");
    loadVkProc(gpi, &c.pfn_vkCmdSetStencilTestEnable, "vkCmdSetStencilTestEnable");
    loadVkProc(gpi, &c.pfn_vkCmdSetColorBlendEnableEXT, "vkCmdSetColorBlendEnableEXT");
    loadVkProc(gpi, &c.pfn_vkCmdSetColorWriteMaskEXT, "vkCmdSetColorWriteMaskEXT");
    loadVkProc(gpi, &c.pfn_vkCmdSetPrimitiveTopology, "vkCmdSetPrimitiveTopology");
    loadVkProc(gpi, &c.pfn_vkCmdSetPrimitiveRestartEnable, "vkCmdSetPrimitiveRestartEnable");
    loadVkProc(gpi, &c.pfn_vkCmdSetDepthBiasEnable, "vkCmdSetDepthBiasEnable");
    loadVkProc(gpi, &c.pfn_vkCmdSetPolygonModeEXT, "vkCmdSetPolygonModeEXT");
    loadVkProc(gpi, &c.pfn_vkCmdSetRasterizationSamplesEXT, "vkCmdSetRasterizationSamplesEXT");
    loadVkProc(gpi, &c.pfn_vkCmdSetSampleMaskEXT, "vkCmdSetSampleMaskEXT");
    loadVkProc(gpi, &c.pfn_vkCmdSetDepthClampEnableEXT, "vkCmdSetDepthClampEnableEXT");
    loadVkProc(gpi, &c.pfn_vkCmdSetAlphaToOneEnableEXT, "vkCmdSetAlphaToOneEnableEXT");
    loadVkProc(gpi, &c.pfn_vkCmdSetAlphaToCoverageEnableEXT, "vkCmdSetAlphaToCoverageEnableEXT");
    loadVkProc(gpi, &c.pfn_vkCmdSetLogicOpEnableEXT, "vkCmdSetLogicOpEnableEXT");
    loadVkProc(gpi, &c.pfn_vkCmdSetViewportWithCount, "vkCmdSetViewportWithCount");
    loadVkProc(gpi, &c.pfn_vkCmdSetScissorWithCount, "vkCmdSetScissorWithCount");
    // Import Shader Object Functions
    loadVkProc(gpi, &c.pfn_vkCreateShadersEXT, "vkCreateShadersEXT");
    loadVkProc(gpi, &c.pfn_vkDestroyShaderEXT, "vkDestroyShaderEXT");
    loadVkProc(gpi, &c.pfn_vkCmdBindShadersEXT, "vkCmdBindShadersEXT");
    loadVkProc(gpi, &c.pfn_vkCmdSetVertexInputEXT, "vkCmdSetVertexInputEXT");
    // Import Descriptor Buffer Functions
    loadVkProc(gpi, &c.pfn_vkCmdBindDescriptorBuffersEXT, "vkCmdBindDescriptorBuffersEXT");
    loadVkProc(gpi, &c.pfn_vkCmdSetDescriptorBufferOffsetsEXT, "vkCmdSetDescriptorBufferOffsetsEXT");
    loadVkProc(gpi, &c.pfn_vkGetDescriptorEXT, "vkGetDescriptorEXT");
    loadVkProc(gpi, &c.pfn_vkGetDescriptorSetLayoutSizeEXT, "vkGetDescriptorSetLayoutSizeEXT");

    return gpi;
}

pub fn loadVkProc(
    handle: anytype, //(instance or device)
    comptime functionPtr: anytype,
    comptime name: []const u8,
) void {
    const proc = c.vkGetDeviceProcAddr(handle, name.ptr);
    functionPtr.* = if (proc) |p| @ptrCast(p) else null;
    if (functionPtr.* == null) std.debug.print("{s} Could not be loaded\n", .{name});
}
