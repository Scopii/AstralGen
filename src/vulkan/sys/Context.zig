const Queue = @import("../types/base/Queue.zig").Queue;
const rc = @import("../../configs/renderConfig.zig");
const sdl = @import("../../modules/sdl.zig").c;
const vhF = @import("../help/Functions.zig");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const vhE = @import("../help/Enums.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

pub const Context = struct {
    alloc: Allocator,
    instance: vk.VkInstance,
    gpu: vk.VkPhysicalDevice,
    gpi: vk.VkDevice,
    graphicsQ: Queue,

    pub fn init(alloc: Allocator) !Context {
        const instance = try createInstance(alloc);
        const gpu = try pickGPU(alloc, instance);
        const familiy = try findGpuFamily(alloc, gpu, vk.VK_QUEUE_GRAPHICS_BIT | vk.VK_QUEUE_COMPUTE_BIT);
        const gpi = try createGPI(alloc, gpu, familiy);

        return .{
            .alloc = alloc,
            .instance = instance,
            .gpu = gpu,
            .gpi = gpi,
            .graphicsQ = Queue.init(gpi, familiy, 0),
        };
    }

    pub fn deinit(self: *const Context) void {
        vk.vkDestroyDevice(self.gpi, null);
        vk.vkDestroyInstance(self.instance, null);
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
    std.debug.print("Vulkan Validation: {}\n", .{rc.VALIDATION});

    var extraCount: u8 = 0;
    var extraValidation: [5]vk.VkValidationFeatureEnableEXT = undefined;

    if (rc.GPU_VALIDATION) {
        extraValidation[0] = vk.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_EXT;
        extraValidation[1] = vk.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_RESERVE_BINDING_SLOT_EXT;
        extraValidation[2] = vk.VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT;
        extraValidation[3] = vk.VK_VALIDATION_FEATURE_ENABLE_DEBUG_PRINTF_EXT;
        extraCount += 4;
    }
    std.debug.print("Extra Validation: {}\n", .{rc.GPU_VALIDATION});

    if (rc.BEST_PRACTICES) {
        extraValidation[extraCount] = vk.VK_VALIDATION_FEATURE_ENABLE_BEST_PRACTICES_EXT;
        extraCount += 1;
    }
    std.debug.print("Best Practices: {}\n", .{rc.BEST_PRACTICES});

    var extraValidationExtensions = vk.VkValidationFeaturesEXT{
        .sType = vk.VK_STRUCTURE_TYPE_VALIDATION_FEATURES_EXT,
        .pNext = null,
        .enabledValidationFeatureCount = extraCount,
        .pEnabledValidationFeatures = &extraValidation,
        .disabledValidationFeatureCount = 0,
        .pDisabledValidationFeatures = null,
    };

    const appInf = vk.VkApplicationInfo{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "AstralGen",
        .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "AstralEngine",
        .engineVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = vk.VK_API_VERSION_1_3,
    };

    std.debug.print("Instance Extensions {}\n", .{extensions.items.len});

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
        if (checkGPU(gpu, vk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) and try checkGPUfeatures(alloc, gpu)) {
            chosen = gpu;
            break;
        }
    }
    if (chosen) |gpu| return gpu;

    for (gpus) |gpu| {
        if (checkGPU(gpu, vk.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) and try checkGPUfeatures(alloc, gpu)) {
            chosen = gpu;
            break;
        }
    }
    if (chosen) |gpu| return gpu;

    std.log.err("No suitable GPUs found\n", .{});
    return error.NoDevice;
}

pub fn checkGPU(gpu: vk.VkPhysicalDevice, deviceType: vk.VkPhysicalDeviceType) bool {
    var driverProps: vk.VkPhysicalDeviceDriverProperties = .{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES };
    var props2: vk.VkPhysicalDeviceProperties2 = .{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &driverProps };
    vk.vkGetPhysicalDeviceProperties2(gpu, &props2);

    std.debug.print("Testing: {s}\n", .{props2.properties.deviceName});

    if (props2.properties.deviceType != deviceType) {
        std.debug.print("Device not discrete GPU!\n", .{});
        return false;
    } else std.debug.print("Device valid\n", .{});

    std.debug.print("Driver: {s} {s}\n", .{ driverProps.driverName, driverProps.driverInfo });
    return true;
}

fn checkGPUfeatures(alloc: Allocator, gpu: vk.VkPhysicalDevice) !bool {
    var extensions: u32 = 0;
    try vhF.check(vk.vkEnumerateDeviceExtensionProperties(gpu, null, &extensions, null), "Failed to enumerate device extensions");

    const supported = try alloc.alloc(vk.VkExtensionProperties, extensions);
    defer alloc.free(supported);
    try vhF.check(vk.vkEnumerateDeviceExtensionProperties(gpu, null, &extensions, supported.ptr), "Failed to get device extensions");

    const required = [_][]const u8{"VK_KHR_swapchain"}; // SHOULD TAKE ACTUAL EXTENSIONS ??
    var matched: u32 = 0;

    for (supported) |extension| {
        for (required) |reqExtension| {
            const extName: [*c]const u8 = @ptrCast(extension.extensionName[0..]);

            const match = std.mem.eql(u8, reqExtension, std.mem.span(extName));
            if (match) {
                matched += 1;
                break;
            }
        }
    }
    return matched == required.len;
}

fn findGpuFamily(alloc: Allocator, gpu: vk.VkPhysicalDevice, queueFlags: vk.VkQueueFlags) !u32 {
    var familyCount: u32 = 0;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, null);

    const families = try alloc.alloc(vk.VkQueueFamilyProperties, familyCount);
    defer alloc.free(families);
    vk.vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, families.ptr);

    for (families, 0..) |family, i| {
        if ((family.queueFlags & queueFlags) != 0) return @intCast(i);
    }
    return error.NoSuitableQueueFamily;
}

fn createGPI(alloc: Allocator, gpu: vk.VkPhysicalDevice, family: u32) !vk.VkDevice {
    var priority: f32 = 1.0;
    var queueInfos = std.array_list.Managed(vk.VkDeviceQueueCreateInfo).init(alloc);
    defer queueInfos.deinit();

    try queueInfos.append(
        vk.VkDeviceQueueCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = family,
            .queueCount = 1,
            .pQueuePriorities = &priority,
        },
    );

    var sup = std.mem.zeroes(DeviceFeatures); // Supported Features
    sup.init(gpu);
    var need = std.mem.zeroes(DeviceFeatures); // Needed Features
    need.init(null);

    var fullSup = true;

    // Untyped Ptr
    fullSup &= checkFeature("Descriptor Untyped Ptr", sup.descUntyped.shaderUntypedPointers, &need.descUntyped.shaderUntypedPointers);

    // Descriptor Heaps
    fullSup &= checkFeature("Descriptor Heaps", sup.descHeaps.descriptorHeap, &need.descHeaps.descriptorHeap);

    // Dynamic State 3
    fullSup &= checkFeature("Polygon Mode", sup.dynState3.extendedDynamicState3PolygonMode, &need.dynState3.extendedDynamicState3PolygonMode);
    fullSup &= checkFeature("Raster Samples", sup.dynState3.extendedDynamicState3RasterizationSamples, &need.dynState3.extendedDynamicState3RasterizationSamples);
    fullSup &= checkFeature("Sample Mask", sup.dynState3.extendedDynamicState3SampleMask, &need.dynState3.extendedDynamicState3SampleMask);
    fullSup &= checkFeature("Depth Clamp", sup.dynState3.extendedDynamicState3DepthClampEnable, &need.dynState3.extendedDynamicState3DepthClampEnable);
    fullSup &= checkFeature("Color Blend", sup.dynState3.extendedDynamicState3ColorBlendEnable, &need.dynState3.extendedDynamicState3ColorBlendEnable);
    fullSup &= checkFeature("Color Blend Equation", sup.dynState3.extendedDynamicState3ColorBlendEquation, &need.dynState3.extendedDynamicState3ColorBlendEquation);
    fullSup &= checkFeature("Color Write Mask", sup.dynState3.extendedDynamicState3ColorWriteMask, &need.dynState3.extendedDynamicState3ColorWriteMask);
    fullSup &= checkFeature("Alpha to Coverage", sup.dynState3.extendedDynamicState3AlphaToCoverageEnable, &need.dynState3.extendedDynamicState3AlphaToCoverageEnable);
    fullSup &= checkFeature("Alpha to One", sup.dynState3.extendedDynamicState3AlphaToOneEnable, &need.dynState3.extendedDynamicState3AlphaToOneEnable);

    // Dynamic State 2
    fullSup &= checkFeature("Extended State 2", sup.dynState2.extendedDynamicState2, &need.dynState2.extendedDynamicState2);
    fullSup &= checkFeature("Extended State 2 Logic Op", sup.dynState2.extendedDynamicState2LogicOp, &need.dynState2.extendedDynamicState2LogicOp);
    fullSup &= checkFeature("Extended State 2 Patch Control", sup.dynState2.extendedDynamicState2PatchControlPoints, &need.dynState2.extendedDynamicState2PatchControlPoints);

    // Vairable Shading Rate
    fullSup &= checkFeature("Pipeline Fragment Shading Rate", sup.shadingRate.pipelineFragmentShadingRate, &need.shadingRate.pipelineFragmentShadingRate);
    fullSup &= checkFeature("Primitive Fragment Shading Rate", sup.shadingRate.primitiveFragmentShadingRate, &need.shadingRate.primitiveFragmentShadingRate);
    fullSup &= checkFeature("Attachment Fragment Shading Rate", sup.shadingRate.attachmentFragmentShadingRate, &need.shadingRate.attachmentFragmentShadingRate);

    // Shader Objects
    fullSup &= checkFeature("Shader Objects", sup.shaderObj.shaderObject, &need.shaderObj.shaderObject);

    // Mesh/Task Shaders
    fullSup &= checkFeature("Mesh Shaders", sup.meshShaders.meshShader, &need.meshShaders.meshShader);
    fullSup &= checkFeature("Task Shaders", sup.meshShaders.taskShader, &need.meshShaders.taskShader);

    // Vk11 Features
    fullSup &= checkFeature("Shader Draw Parameters", sup.vk11.shaderDrawParameters, &need.vk11.shaderDrawParameters);
    fullSup &= checkFeature("Storage Buffer 16Bit Access", sup.vk11.storageBuffer16BitAccess, &need.vk11.storageBuffer16BitAccess);
    fullSup &= checkFeature("Uniform/Storage Buffer 16Bit Access", sup.vk11.uniformAndStorageBuffer16BitAccess, &need.vk11.uniformAndStorageBuffer16BitAccess);

    // Vk12 Features
    fullSup &= checkFeature("Buffer Device Address", sup.vk12.bufferDeviceAddress, &need.vk12.bufferDeviceAddress);
    fullSup &= checkFeature("Descriptor Indexing", sup.vk12.descriptorIndexing, &need.vk12.descriptorIndexing);
    fullSup &= checkFeature("Desc-Bind StorageImg Update After Bind", sup.vk12.descriptorBindingStorageImageUpdateAfterBind, &need.vk12.descriptorBindingStorageImageUpdateAfterBind);
    fullSup &= checkFeature("Desc-Bind SampledImg Update After Bind", sup.vk12.descriptorBindingSampledImageUpdateAfterBind, &need.vk12.descriptorBindingSampledImageUpdateAfterBind);
    fullSup &= checkFeature("Descriptor Binding Partially Bound", sup.vk12.descriptorBindingPartiallyBound, &need.vk12.descriptorBindingPartiallyBound);
    fullSup &= checkFeature("Timeline Semaphores", sup.vk12.timelineSemaphore, &need.vk12.timelineSemaphore);
    fullSup &= checkFeature("Tunetime Descriptor Array", sup.vk12.runtimeDescriptorArray, &need.vk12.runtimeDescriptorArray);
    fullSup &= checkFeature("Shader StorageImg Array-NonUniform-Indexing", sup.vk12.shaderStorageImageArrayNonUniformIndexing, &need.vk12.shaderStorageImageArrayNonUniformIndexing);
    fullSup &= checkFeature("Shader SampledImg Array-NonUniform-Indexing", sup.vk12.shaderSampledImageArrayNonUniformIndexing, &need.vk12.shaderSampledImageArrayNonUniformIndexing);
    fullSup &= checkFeature("Shader Float 16", sup.vk12.shaderFloat16, &need.vk12.shaderFloat16);
    fullSup &= checkFeature("Shader Buffer Int64 Atomics", sup.vk12.shaderBufferInt64Atomics, &need.vk12.shaderBufferInt64Atomics);

    // Vk13 Features
    fullSup &= checkFeature("Dynamic Rendering", sup.vk13.dynamicRendering, &need.vk13.dynamicRendering);
    fullSup &= checkFeature("Synchronization 2", sup.vk13.synchronization2, &need.vk13.synchronization2);
    fullSup &= checkFeature("Maintenance 4", sup.vk13.maintenance4, &need.vk13.maintenance4);

    // Vk14 Features
    fullSup &= checkFeature("Maintenance 5", sup.maint5.maintenance5, &need.maint5.maintenance5);

    // Device2 Features
    fullSup &= checkFeature("Shader Int 64", sup.devFeatures2.features.shaderInt64, &need.devFeatures2.features.shaderInt64);
    fullSup &= checkFeature("Wide Lines", sup.devFeatures2.features.wideLines, &need.devFeatures2.features.wideLines);

    if (fullSup == false) {
        std.debug.print("Device does not Support all needed Features! Exiting\n", .{});
        return error.MissingRequiredFeature;
    }

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
        "VK_EXT_vertex_input_dynamic_state",
        "VK_EXT_descriptor_buffer", // Needed for GPU-AV for some reason
    };

    const createInf = vk.VkDeviceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &need.devFeatures2,
        .pQueueCreateInfos = queueInfos.items.ptr,
        .queueCreateInfoCount = @intCast(queueInfos.items.len),
        .pEnabledFeatures = null,
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

fn checkFeature(name: []const u8, deviceBool: vk.VkBool32, featureBoolPtr: *vk.VkBool32) bool {
    if (deviceBool == vk.VK_FALSE) {
        std.log.err("Hardware Feature Missing: {s}", .{name});
        return false;
    }
    if (deviceBool == vk.VK_TRUE) featureBoolPtr.* = vk.VK_TRUE;
    return true;
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

const DeviceFeatures = struct {
    descUntyped: vk.VkPhysicalDeviceShaderUntypedPointersFeaturesKHR,
    descHeaps: vk.VkPhysicalDeviceDescriptorHeapFeaturesEXT,
    dynState3: vk.VkPhysicalDeviceExtendedDynamicState3FeaturesEXT,
    dynState2: vk.VkPhysicalDeviceExtendedDynamicState2FeaturesEXT,
    shadingRate: vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR,
    shaderObj: vk.VkPhysicalDeviceShaderObjectFeaturesEXT,
    meshShaders: vk.VkPhysicalDeviceMeshShaderFeaturesEXT,
    vk11: vk.VkPhysicalDeviceVulkan11Features,
    vk12: vk.VkPhysicalDeviceVulkan12Features,
    vk13: vk.VkPhysicalDeviceVulkan13Features,
    maint5: vk.VkPhysicalDeviceMaintenance5FeaturesKHR,
    devFeatures2: vk.VkPhysicalDeviceFeatures2,

    pub fn init(self: *DeviceFeatures, gpu: ?vk.VkPhysicalDevice) void {
        self.descUntyped.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_UNTYPED_POINTERS_FEATURES_KHR;
        self.descUntyped.pNext = null;

        self.descHeaps.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_HEAP_FEATURES_EXT;
        self.descHeaps.pNext = &self.descUntyped;

        self.dynState3.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT;
        self.dynState3.pNext = &self.descHeaps;

        self.dynState2.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT;
        self.dynState2.pNext = &self.dynState3;

        self.shadingRate.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR;
        self.shadingRate.pNext = &self.dynState2;

        self.shaderObj.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT;
        self.shaderObj.pNext = &self.shadingRate;

        self.meshShaders.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT;
        self.meshShaders.pNext = &self.shaderObj;

        self.vk11.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
        self.vk11.pNext = &self.meshShaders;

        self.vk12.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
        self.vk12.pNext = &self.vk11;

        self.vk13.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES;
        self.vk13.pNext = &self.vk12;

        self.maint5.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_5_FEATURES_KHR;
        self.maint5.pNext = &self.vk13;

        self.devFeatures2.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
        self.devFeatures2.pNext = &self.maint5;

        if (gpu) |validGpu| vk.vkGetPhysicalDeviceFeatures2(validGpu, &self.devFeatures2);
    }
};
