const Queue = @import("../types/base/Queue.zig").Queue;
const rc = @import("../../configs/renderConfig.zig");
const sdl = @import("../../modules/sdl.zig").c;
const vhF = @import("../help/Functions.zig");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const vhE = @import("../help/Enums.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

pub const QueueFamilies = struct {
    graphics: u32,
    present: u32,
};

pub const Context = struct {
    alloc: Allocator,
    instance: vk.VkInstance,
    gpu: vk.VkPhysicalDevice,
    families: QueueFamilies,
    gpi: vk.VkDevice,
    graphicsQ: Queue,
    presentQ: Queue,

    pub fn init(alloc: Allocator) !Context {
        const instance = try createInstance(alloc);

        const gpu = try pickGPU(alloc, instance);
        const families = try checkGPUfamilies(alloc, gpu);
        const gpi = try createGPI(alloc, gpu, families);

        const graphicsQ = Queue.init(gpi, families.graphics, 0);
        const presentQ = Queue.init(gpi, families.present, 0);

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
        vk.vkDestroyDevice(self.gpi, null);
        vk.vkDestroyInstance(self.instance, null);
    }

    fn pickPresentMode(self: *const Context) !vk.VkPresentModeKHR {
        const gpu = self.gpu;
        const surface = self.surface;

        var modeCount: u32 = 0;
        try vhE.check(vk.vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &modeCount, null), "Failed to get present mode count");
        if (modeCount == 0) return vk.VK_PRESENT_MODE_FIFO_KHR; // FIFO is always supported

        const modes = try self.alloc.alloc(vk.VkPresentModeKHR, modeCount);
        defer self.alloc.free(modes);

        try vhE.check(vk.vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &modeCount, modes.ptr), "Failed to get present modes");
        // Prefer mailbox (triple buffering), then immediate, fallback to FIFO
        for (modes) |mode| if (mode == vk.VK_PRESENT_MODE_MAILBOX_KHR) return mode;
        for (modes) |mode| if (mode == vk.VK_PRESENT_MODE_IMMEDIATE_KHR) return mode;
        return vk.VK_PRESENT_MODE_FIFO_KHR;
    }
};

pub fn createInstance(alloc: Allocator) !vk.VkInstance {
    var extensions = std.array_list.Managed([*c]const u8).init(alloc);
    defer extensions.deinit();
    var layers = std.array_list.Managed([*c]const u8).init(alloc);
    defer layers.deinit();

    // get required extensions
    var extCount: u32 = 0;
    const reqExtensions = sdl.SDL_Vulkan_GetInstanceExtensions(&extCount);
    for (0..extCount) |i| try extensions.append(reqExtensions[i]);

    if (rc.VALIDATION) {
        try extensions.append("VK_EXT_debug_utils");
        try layers.append("VK_LAYER_KHRONOS_validation");
    }

    var extraValidationFeatures = switch (rc.BEST_PRACTICES) {
        true => if (rc.GPU_VALIDATION == true) [_]vk.VkValidationFeatureEnableEXT{
            vk.VK_VALIDATION_FEATURE_ENABLE_BEST_PRACTICES_EXT,
            vk.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_EXT,
            vk.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_RESERVE_BINDING_SLOT_EXT,
            vk.VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT,
            vk.VK_VALIDATION_FEATURE_ENABLE_DEBUG_PRINTF_EXT,
        } else [_]vk.VkValidationFeatureEnableEXT{vk.VK_VALIDATION_FEATURE_ENABLE_BEST_PRACTICES_EXT},
        false => [_]vk.VkValidationFeatureEnableEXT{
            vk.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_EXT,
            vk.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_RESERVE_BINDING_SLOT_EXT, // ?? Needs Descriptor ?
            vk.VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT,
            vk.VK_VALIDATION_FEATURE_ENABLE_DEBUG_PRINTF_EXT,
        },
    };

    std.debug.print("Vulkan Validation: {}\n", .{rc.VALIDATION});
    std.debug.print("Extra Validation: {}\n", .{rc.GPU_VALIDATION});
    std.debug.print("Best Practices: {}\n", .{rc.BEST_PRACTICES});

    var extraValidationExtensions = vk.VkValidationFeaturesEXT{
        .sType = vk.VK_STRUCTURE_TYPE_VALIDATION_FEATURES_EXT,
        .pNext = null,
        .enabledValidationFeatureCount = extraValidationFeatures.len,
        .pEnabledValidationFeatures = &extraValidationFeatures,
        .disabledValidationFeatureCount = 0,
        .pDisabledValidationFeatures = null,
    };

    std.debug.print("Instance Extensions {}\n", .{extensions.items.len});

    const appInf = vk.VkApplicationInfo{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "AstralGen",
        .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "AstralEngine",
        .engineVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = vk.VK_API_VERSION_1_3,
    };

    const instanceInf = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = if (rc.GPU_VALIDATION or rc.BEST_PRACTICES) @ptrCast(&extraValidationExtensions) else null,
        .flags = 0,
        .pApplicationInfo = &appInf,
        .enabledLayerCount = @intCast(layers.items.len),
        .ppEnabledLayerNames = layers.items.ptr,
        .enabledExtensionCount = @intCast(extensions.items.len),
        .ppEnabledExtensionNames = extensions.items.ptr,
    };

    var instance: vk.VkInstance = undefined;
    try vhF.check(vk.vkCreateInstance(&instanceInf, null, &instance), "Unable to create Vulkan instance!");
    return instance;
}

// DEVICE //

fn pickGPU(alloc: Allocator, instance: vk.VkInstance) !vk.VkPhysicalDevice {
    var gpuCount: u32 = 0;
    try vhF.check(vk.vkEnumeratePhysicalDevices(instance, &gpuCount, null), "Failed to enumerate GPUs");
    if (gpuCount == 0) return error.NoDevice;

    const gpus = try alloc.alloc(vk.VkPhysicalDevice, gpuCount);
    defer alloc.free(gpus);
    try vhF.check(vk.vkEnumeratePhysicalDevices(instance, &gpuCount, gpus.ptr), "Failed to get GPUs");

    var chosen: ?vk.VkPhysicalDevice = null;
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

pub fn checkGPU(gpu: vk.VkPhysicalDevice) bool {
    var properties: vk.VkPhysicalDeviceProperties = undefined;
    vk.vkGetPhysicalDeviceProperties(gpu, &properties);
    var features: vk.VkPhysicalDeviceFeatures = undefined;
    vk.vkGetPhysicalDeviceFeatures(gpu, &features);

    std.debug.print("Testing: {s}\n", .{properties.deviceName});
    if (properties.deviceType != vk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
        std.debug.print("Device not discrete GPU\n", .{});
        return false;
    }
    return true;
}

fn checkGPUfeatures(alloc: Allocator, gpu: vk.VkPhysicalDevice) !bool {
    var extensions: u32 = 0;
    try vhF.check(vk.vkEnumerateDeviceExtensionProperties(gpu, null, &extensions, null), "Failed to enumerate device extensions");

    const supported = try alloc.alloc(vk.VkExtensionProperties, extensions);
    defer alloc.free(supported);
    try vhF.check(vk.vkEnumerateDeviceExtensionProperties(gpu, null, &extensions, supported.ptr), "Failed to get device extensions");

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

// fn findFamily(families: []const vk.VkQueueFamilyProperties) ?u32 {
//     for (families, 0..) |family, i| {
//         if (family.queueCount > 0 and (family.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) and (family.queueFlags & vk.VK_QUEUE_COMPUTE_BIT != 0)) return @intCast(i);
//     }
//     return null;
// }

// // Not in use because using the same Family because most Graphics Queues support Presentation and this avoids creating a Surface for setup
// fn findPresentFamily(families: []const vk.VkQueueFamilyProperties, gpu: vk.VkPhysicalDevice) !?u32 {
//     for (families, 0..) |family, i| {
//         var presentSupport: vk.VkBool32 = vk.VK_FALSE;
//         try vh.check(vk.vkGetPhysicalDeviceSurfaceSupportKHR(gpu, @intCast(i), null, &presentSupport), "Failed to get present support");
//         if (presentSupport == vk.VK_TRUE and family.queueCount != 0) return @intCast(i);
//     }
//     return null;
// }

fn checkGPUfamilies(alloc: Allocator, gpu: vk.VkPhysicalDevice) !QueueFamilies {
    var familyCount: u32 = 0;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, null);

    const families = try alloc.alloc(vk.VkQueueFamilyProperties, familyCount);
    defer alloc.free(families);
    vk.vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, families.ptr);

    for (families, 0..) |family, i| {
        const hasGraphics = (family.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT) != 0;
        //var hasPresent: vk.VkBool32 = vk.VK_FALSE;
        //vk.vkGetPhysicalDeviceSurfaceSupportKHR(gpu, @intCast(i), surface, &hasPresent);
        if (hasGraphics == true) {
            return QueueFamilies{ .graphics = @intCast(i), .present = @intCast(i) };
        }
    }
    return error.NoSuitableQueueFamily;
}

fn createGPI(alloc: Allocator, gpu: vk.VkPhysicalDevice, families: QueueFamilies) !vk.VkDevice {
    var priority: f32 = 1.0;
    var queueInfos = std.array_list.Managed(vk.VkDeviceQueueCreateInfo).init(alloc);
    defer queueInfos.deinit();

    const graphicsInf = vk.VkDeviceQueueCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = families.graphics,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    };
    try queueInfos.append(graphicsInf);

    if (families.graphics != families.present) {
        const presentInf = vk.VkDeviceQueueCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = families.present,
            .queueCount = 1,
            .pQueuePriorities = &priority,
        };
        try queueInfos.append(presentInf);
    }

    var features: vk.VkPhysicalDeviceFeatures = undefined;
    vk.vkGetPhysicalDeviceFeatures(gpu, &features);
    features.shaderInt64 = vk.VK_TRUE;

    var descUntypedFeatures = vk.VkPhysicalDeviceShaderUntypedPointersFeaturesKHR{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_UNTYPED_POINTERS_FEATURES_KHR,
        .pNext = null,
        .shaderUntypedPointers = vk.VK_TRUE,
    };

    var descHeapFeatures = vk.VkPhysicalDeviceDescriptorHeapFeaturesEXT{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_HEAP_FEATURES_EXT,
        .pNext = &descUntypedFeatures,
        .descriptorHeap = vk.VK_TRUE,
        .descriptorHeapCaptureReplay = vk.VK_FALSE,
    };

    var features2 = vk.VkPhysicalDeviceFeatures2{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
        .pNext = &descHeapFeatures,
    };
    vk.vkGetPhysicalDeviceFeatures2(gpu, &features2);

    if (descHeapFeatures.descriptorHeap == vk.VK_TRUE) {
        std.debug.print("Descriptor heaps supported!\n", .{});
    } else {
        std.debug.print("Descriptor heaps NOT supported - stick with descriptor buffers\n", .{});
    }

    var dynamicState3Features = vk.VkPhysicalDeviceExtendedDynamicState3FeaturesEXT{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT,
        .pNext = &descHeapFeatures,
        .extendedDynamicState3PolygonMode = vk.VK_TRUE,
        .extendedDynamicState3RasterizationSamples = vk.VK_TRUE,
        .extendedDynamicState3SampleMask = vk.VK_TRUE,
        .extendedDynamicState3DepthClampEnable = vk.VK_TRUE,
        .extendedDynamicState3ColorBlendEnable = vk.VK_TRUE,
        .extendedDynamicState3ColorBlendEquation = vk.VK_TRUE,
        .extendedDynamicState3ColorWriteMask = vk.VK_TRUE,
        .extendedDynamicState3AlphaToCoverageEnable = vk.VK_TRUE,
        .extendedDynamicState3AlphaToOneEnable = vk.VK_TRUE,
    };

    var dynamicState2Features = vk.VkPhysicalDeviceExtendedDynamicState2FeaturesEXT{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT,
        .pNext = &dynamicState3Features,
        .extendedDynamicState2 = vk.VK_TRUE,
        .extendedDynamicState2LogicOp = vk.VK_TRUE,
        .extendedDynamicState2PatchControlPoints = vk.VK_TRUE,
    };

    var shadingRateFeatures = vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR,
        .pNext = &dynamicState2Features,
        .pipelineFragmentShadingRate = vk.VK_TRUE, // for cmd call
        .primitiveFragmentShadingRate = vk.VK_TRUE, // for Mesh Shader writing
        .attachmentFragmentShadingRate = vk.VK_FALSE, // for images to control rate
    };

    var shaderObjFeatures = vk.VkPhysicalDeviceShaderObjectFeaturesEXT{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT,
        .pNext = &shadingRateFeatures,
        .shaderObject = vk.VK_TRUE,
    };

    var meshShaderFeatures = vk.VkPhysicalDeviceMeshShaderFeaturesEXT{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT,
        .pNext = &shaderObjFeatures,
        .taskShader = vk.VK_TRUE,
        .meshShader = vk.VK_TRUE,
    };

    var vk11Features = vk.VkPhysicalDeviceVulkan11Features{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
        .pNext = &meshShaderFeatures,
        .shaderDrawParameters = vk.VK_TRUE,
        .storageBuffer16BitAccess = vk.VK_TRUE, // Allows reading/writing 16-bit values to SSBOs
        .uniformAndStorageBuffer16BitAccess = vk.VK_TRUE, // UBOs too ^^
    };

    var vk12Features = vk.VkPhysicalDeviceVulkan12Features{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .bufferDeviceAddress = vk.VK_TRUE,
        .descriptorIndexing = vk.VK_TRUE,
        .descriptorBindingStorageImageUpdateAfterBind = vk.VK_TRUE,
        .descriptorBindingSampledImageUpdateAfterBind = vk.VK_TRUE,
        .descriptorBindingPartiallyBound = vk.VK_TRUE,
        .timelineSemaphore = vk.VK_TRUE,
        .runtimeDescriptorArray = vk.VK_TRUE,
        .shaderStorageImageArrayNonUniformIndexing = vk.VK_TRUE,
        .shaderSampledImageArrayNonUniformIndexing = vk.VK_TRUE,
        .shaderFloat16 = vk.VK_TRUE,
        .shaderBufferInt64Atomics = vk.VK_TRUE,
        .pNext = &vk11Features,
    };

    var vk13Features = vk.VkPhysicalDeviceVulkan13Features{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .dynamicRendering = vk.VK_TRUE,
        .synchronization2 = vk.VK_TRUE,
        .maintenance4 = vk.VK_TRUE,
        .pNext = &vk12Features,
    };

    const vk14Features = vk.VkPhysicalDeviceVulkan14Features{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_4_FEATURES,
        .maintenance5 = vk.VK_TRUE,
        .pNext = &vk13Features,
    };

    const gpuExtensions = [_][*c]const u8{
        "VK_KHR_swapchain",
        "VK_EXT_mesh_shader",
        "VK_EXT_shader_object",
        "VK_EXT_extended_dynamic_state",
        "VK_EXT_extended_dynamic_state2",
        "VK_EXT_extended_dynamic_state3",
        "VK_EXT_conservative_rasterization",
        "VK_KHR_fragment_shading_rate",
        "VK_KHR_shader_non_semantic_info",
        "VK_EXT_descriptor_heap",
        "VK_KHR_shader_untyped_pointers",
        "VK_KHR_maintenance5",
    };

    const createInf = vk.VkDeviceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &vk14Features,
        .pQueueCreateInfos = queueInfos.items.ptr,
        .queueCreateInfoCount = @intCast(queueInfos.items.len),
        .pEnabledFeatures = &features,
        .enabledExtensionCount = gpuExtensions.len,
        .ppEnabledExtensionNames = &gpuExtensions,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
    };
    std.debug.print("Queues: {}\n", .{queueInfos.items.len});
    var gpi: vk.VkDevice = undefined;
    try vhF.check(vk.vkCreateDevice(gpu, &createInf, null, &gpi), "Unable to create Vulkan device!");

    // Draw Commands (Mesh & Indirect)
    try loadVkProc(gpi, &vkFn.vkCmdDrawMeshTasksEXT, "vkCmdDrawMeshTasksEXT");
    try loadVkProc(gpi, &vkFn.vkCmdDrawMeshTasksIndirectEXT, "vkCmdDrawMeshTasksIndirectEXT");

    // Shader Objects
    try loadVkProc(gpi, &vkFn.vkCreateShadersEXT, "vkCreateShadersEXT");
    try loadVkProc(gpi, &vkFn.vkDestroyShaderEXT, "vkDestroyShaderEXT");
    try loadVkProc(gpi, &vkFn.vkCmdBindShadersEXT, "vkCmdBindShadersEXT");

    // Descriptor Heaps
    try loadVkProc(gpi, &vkFn.vkWriteResourceDescriptorsEXT, "vkWriteResourceDescriptorsEXT");
    try loadVkProc(gpi, &vkFn.vkWriteSamplerDescriptorsEXT, "vkWriteSamplerDescriptorsEXT");
    try loadVkProc(gpi, &vkFn.vkCmdBindResourceHeapEXT, "vkCmdBindResourceHeapEXT");
    try loadVkProc(gpi, &vkFn.vkCmdBindSamplerHeapEXT, "vkCmdBindSamplerHeapEXT");
    try loadVkProc(gpi, &vkFn.vkCmdPushDataEXT, "vkCmdPushDataEXT");

    // Extended Dynamic State 3
    try loadVkProc(gpi, &vkFn.vkCmdSetPolygonModeEXT, "vkCmdSetPolygonModeEXT");
    try loadVkProc(gpi, &vkFn.vkCmdSetRasterizationSamplesEXT, "vkCmdSetRasterizationSamplesEXT");
    try loadVkProc(gpi, &vkFn.vkCmdSetSampleMaskEXT, "vkCmdSetSampleMaskEXT");
    try loadVkProc(gpi, &vkFn.vkCmdSetDepthClampEnableEXT, "vkCmdSetDepthClampEnableEXT");
    try loadVkProc(gpi, &vkFn.vkCmdSetColorBlendEnableEXT, "vkCmdSetColorBlendEnableEXT");
    try loadVkProc(gpi, &vkFn.vkCmdSetColorBlendEquationEXT, "vkCmdSetColorBlendEquationEXT");
    try loadVkProc(gpi, &vkFn.vkCmdSetColorWriteMaskEXT, "vkCmdSetColorWriteMaskEXT");
    try loadVkProc(gpi, &vkFn.vkCmdSetAlphaToOneEnableEXT, "vkCmdSetAlphaToOneEnableEXT");
    try loadVkProc(gpi, &vkFn.vkCmdSetAlphaToCoverageEnableEXT, "vkCmdSetAlphaToCoverageEnableEXT");

    // Extended Dynamic State 2
    try loadVkProc(gpi, &vkFn.vkCmdSetVertexInputEXT, "vkCmdSetVertexInputEXT");
    try loadVkProc(gpi, &vkFn.vkCmdSetLogicOpEnableEXT, "vkCmdSetLogicOpEnableEXT");
    try loadVkProc(gpi, &vkFn.vkCmdSetLogicOpEXT, "vkCmdSetLogicOpEXT");

    // Conservative Rasterization
    try loadVkProc(gpi, &vkFn.vkCmdSetConservativeRasterizationModeEXT, "vkCmdSetConservativeRasterizationModeEXT");

    // Fragment Shading Rate
    try loadVkProc(gpi, &vkFn.vkCmdSetFragmentShadingRateKHR, "vkCmdSetFragmentShadingRateKHR");

    // Debug
    if (rc.VALIDATION == true) try loadVkProc(gpi, &vkFn.vkSetDebugUtilsObjectNameEXT, "vkSetDebugUtilsObjectNameEXT");

    return gpi;
}

fn checkFeature(name: []const u8, supportBool: vk.VkBool32) !void {
    if (supportBool == vk.VK_FALSE) {
        std.log.err("Hardware Feature Missing: {s}", .{name});
        return error.FeatureNotSupported;
    }
}

// Handle can be instance or device
pub fn loadVkProc(handle: anytype, comptime functionPtr: anytype, comptime name: []const u8) !void {
    const proc = vk.vkGetDeviceProcAddr(handle, name.ptr);
    functionPtr.* = if (proc) |p| @ptrCast(p) else null;
    if (functionPtr.* == null) {
        std.log.err("{s} Could not be loaded\n", .{name});
        return error.CouldntLoadFunctionPointer;
    }
}
