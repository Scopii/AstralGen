const Queue = @import("../types/base/Queue.zig").Queue;
const rc = @import("../../.configs/renderConfig.zig");
const sdl = @import("../../.modules/sdl.zig").c;
const vhF = @import("../help/Functions.zig");
const vk = @import("../../.modules/vk.zig").c;
const vkFn = @import("../../.modules/vk.zig").vkFn;
const vhE = @import("../help/Enums.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

pub const VulkanLoad = struct {
    functionPtr: *anyopaque,
    name: [*:0]const u8,
};

pub const Context = struct {
    alloc: Allocator,
    instance: vk.VkInstance,
    gpu: vk.VkPhysicalDevice,
    gpi: vk.VkDevice,
    graphicsQ: Queue,
    meshTaskSupp: bool,

    pub fn init(alloc: Allocator) !Context {
        const instance = try createInstance(alloc);
        const gpu = try pickGPU(alloc, instance);
        const familiy = try findGpuFamily(alloc, gpu, vk.VK_QUEUE_GRAPHICS_BIT | vk.VK_QUEUE_COMPUTE_BIT);
        const gpiInf = try createGPI(alloc, gpu, familiy);

        return .{
            .alloc = alloc,
            .instance = instance,
            .gpu = gpu,
            .gpi = gpiInf.gpi,
            .graphicsQ = Queue.init(gpiInf.gpi, familiy, 0),
            .meshTaskSupp = gpiInf.meshSupport,
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
        //try layers.append("VK_EXT_layer_settings");
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

    // // Layer settings (equivalent to vkconfig JSON, chains into instanceInf.pNext)
    // const layerName: [*c]const u8 = "VK_LAYER_KHRONOS_validation";
    // const settingNames = [_][*c]const u8{
    //     "enables", // fine-grained enables
    //     "gpuav_enable", // GPU-AV on/off
    //     "gpuav_descriptor_checks",
    //     "printf_enable",
    // };
    // const enableVal: [*c]const u8 = if (rc.GPU_VALIDATION) "VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_EXT" else "";
    // // VkLayerSettingEXT per setting...
    // var layerSettings: [4]vk.VkLayerSettingEXT = .{
    //     .{ .pLayerName = layerName, .pSettingName = settingNames[0], .type = vk.VK_LAYER_SETTING_TYPE_STRING_EXT, .valueCount = 1, .pValues = &enableVal },
    //     // ... etc
    // };
    // var layerSettingsInf = vk.VkLayerSettingsCreateInfoEXT{
    //     .sType = vk.VK_STRUCTURE_TYPE_LAYER_SETTINGS_CREATE_INFO_EXT,
    //     .pNext = if (rc.GPU_VALIDATION or rc.BEST_PRACTICES) @ptrCast(&extraValidationExtensions) else null, // chain after existing
    //     .settingCount = layerSettings.len,
    //     .pSettings = &layerSettings,
    // };

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
        .pNext = if (rc.GPU_VALIDATION or rc.BEST_PRACTICES) @ptrCast(&extraValidationExtensions) else null, // layerSettingsInf
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

fn createGPI(alloc: Allocator, gpu: vk.VkPhysicalDevice, family: u32) !struct { gpi: vk.VkDevice, meshSupport: bool } {
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

    var enabledExts = try std.array_list.Managed([*c]const u8).initCapacity(alloc, 32);
    defer enabledExts.deinit();
    var enabledStructs = try std.array_list.Managed(*vk.VkBaseOutStructure).initCapacity(alloc, 32);
    defer enabledStructs.deinit();
    var functionLoads = try std.array_list.Managed(VulkanLoad).initCapacity(alloc, 64);
    defer functionLoads.deinit();

    var dev2 = try checkDeviceFeatures2(gpu);
    if (dev2) |*str| try enabledStructs.append(@ptrCast(str));

    var robust2 = try checkRobustness2(&enabledExts, gpu);
    if (robust2) |*str| if (rc.ROBUST_VALIDATION == true) try enabledStructs.append(@ptrCast(str));

    var untypedPtr = try checkShaderUntypedPtr(&enabledExts, gpu);
    if (untypedPtr) |*str| try enabledStructs.append(@ptrCast(str));

    var descHeaps = try checkDescriptorHeaps(&enabledExts, gpu, &functionLoads);
    if (descHeaps) |*str| try enabledStructs.append(@ptrCast(str));

    var dynamicState3 = try checkDynamicState3(&enabledExts, gpu, &functionLoads);
    if (dynamicState3) |*str| try enabledStructs.append(@ptrCast(str));

    var dynamicState2 = try checkDynamicState2(&enabledExts, gpu, &functionLoads);
    if (dynamicState2) |*str| try enabledStructs.append(@ptrCast(str));

    var shadingRate = try checkFragmentShadingRate(&enabledExts, gpu, &functionLoads);
    if (shadingRate) |*str| try enabledStructs.append(@ptrCast(str));

    var shaderObj = try checkShaderObjects(&enabledExts, gpu, &functionLoads);
    if (shaderObj) |*str| try enabledStructs.append(@ptrCast(str));

    var meshShader = try checkMeshShaders(&enabledExts, gpu, &functionLoads);
    if (meshShader) |*str| try enabledStructs.append(@ptrCast(str));

    var vk11 = try checkVulkan11Features(gpu);
    if (vk11) |*str| try enabledStructs.append(@ptrCast(str));

    var vk12 = try checkVulkan12Features(gpu);
    if (vk12) |*str| try enabledStructs.append(@ptrCast(str));

    var vk13 = try checkVulkan13Features(gpu);
    if (vk13) |*str| try enabledStructs.append(@ptrCast(str));

    var maint5 = try checkMaintenance5Features(&enabledExts, gpu);
    if (maint5) |*str| try enabledStructs.append(@ptrCast(str));

    if (meshShader == null) {
        std.debug.print("Device does not Support Mesh/Task Shader Features!\n", .{});
    }

    if (dev2 == null or
        robust2 == null or
        untypedPtr == null or
        descHeaps == null or
        dynamicState3 == null or
        dynamicState2 == null or
        shadingRate == null or
        shaderObj == null or
        meshShader == null or
        vk11 == null or
        vk12 == null or
        vk13 == null or
        maint5 == null)
    {
        std.debug.print("Device does not Support all needed Features! Exiting\n", .{});
        return error.MissingRequiredFeature;
    }

    for (0..enabledStructs.items.len - 1) |i| {
        enabledStructs.items[i].pNext = enabledStructs.items[i + 1];
    }

    try enabledExts.append("VK_KHR_swapchain");
    try enabledExts.append("VK_EXT_extended_dynamic_state");
    try enabledExts.append("VK_EXT_conservative_rasterization");
    try enabledExts.append("VK_KHR_shader_non_semantic_info");
    try enabledExts.append("VK_EXT_vertex_input_dynamic_state");
    try enabledExts.append("VK_EXT_descriptor_buffer"); // Needed for GPU-AV for some reason

    const createInf = vk.VkDeviceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = if (enabledStructs.items.len > 0) enabledStructs.items[0] else null,
        .pQueueCreateInfos = queueInfos.items.ptr,
        .queueCreateInfoCount = @intCast(queueInfos.items.len),
        .pEnabledFeatures = null,
        .enabledExtensionCount = @intCast(enabledExts.items.len),
        .ppEnabledExtensionNames = enabledExts.items.ptr,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
    };
    std.debug.print("Queues: {}\n", .{queueInfos.items.len});
    var gpi: vk.VkDevice = undefined;
    try vhF.check(vk.vkCreateDevice(gpu, &createInf, null, &gpi), "Unable to create Vulkan device!");

    for (functionLoads.items) |fnLoad| {
        const proc = vk.vkGetDeviceProcAddr(gpi, fnLoad.name);
        if (proc == null) {
            std.log.err("{s} Could not be loaded\n", .{fnLoad.name});
            return error.CouldntLoadFunctionPointer;
        }
        const target: *vk.PFN_vkVoidFunction = @ptrCast(@alignCast(fnLoad.functionPtr));
        target.* = proc;
    }

    // Debug
    if (rc.VALIDATION == true) {
        try loadVkProc(gpi, &vkFn.vkSetDebugUtilsObjectNameEXT, "vkSetDebugUtilsObjectNameEXT");
        try loadVkProc(gpi, &vkFn.vkCmdBeginDebugUtilsLabelEXT, "vkCmdBeginDebugUtilsLabelEXT");
        try loadVkProc(gpi, &vkFn.vkCmdEndDebugUtilsLabelEXT, "vkCmdEndDebugUtilsLabelEXT");
    }

    return .{
        .gpi = gpi,
        .meshSupport = if (meshShader != null) true else false,
    };
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
pub fn loadVkProc(handle: vk.VkDevice, ptr: anytype, comptime name: [*:0]const u8) !void {
    const proc = vk.vkGetDeviceProcAddr(handle, name);
    if (proc == null) {
        std.log.err("{s} Could not be loaded\n", .{name});
        return error.CouldntLoadFunctionPointer;
    }
    ptr.* = @ptrCast(proc);
}

fn GetFnType(comptime function: anytype) type {
    const Ret = @typeInfo(@TypeOf(function)).@"fn".return_type.?;
    const NoError = @typeInfo(Ret).error_union.payload;
    return @typeInfo(NoError).optional.child;
}

fn fillFeatureStruct(featureStructPtr: *anyopaque, gpu: vk.VkPhysicalDevice) void {
    var devFeatures2 = vk.VkPhysicalDeviceFeatures2{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 };
    devFeatures2.pNext = featureStructPtr;
    vk.vkGetPhysicalDeviceFeatures2(gpu, &devFeatures2);
}

fn checkRobustness2(enabledExts: *std.array_list.Managed([*c]const u8), gpu: vk.VkPhysicalDevice) !?vk.VkPhysicalDeviceRobustness2FeaturesEXT {
    var sup = GetFnType(checkRobustness2){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Robust Buffer Access 2", sup.robustBufferAccess2, &need.robustBufferAccess2);
    fullSup &= checkFeature("Robust Image Access 2", sup.robustImageAccess2, &need.robustImageAccess2);

    if (fullSup) {
        try enabledExts.append("VK_EXT_robustness2");
        return need;
    }
    return null;
}

fn checkShaderUntypedPtr(enabledExts: *std.array_list.Managed([*c]const u8), gpu: vk.VkPhysicalDevice) !?vk.VkPhysicalDeviceShaderUntypedPointersFeaturesKHR {
    var sup = GetFnType(checkShaderUntypedPtr){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_UNTYPED_POINTERS_FEATURES_KHR };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Descriptor Untyped Ptr", sup.shaderUntypedPointers, &need.shaderUntypedPointers);

    if (fullSup) {
        try enabledExts.append("VK_KHR_shader_untyped_pointers");
        return need;
    }
    return null;
}

fn checkDescriptorHeaps(
    enabledExts: *std.array_list.Managed([*c]const u8),
    gpu: vk.VkPhysicalDevice,
    fnLoads: *std.array_list.Managed(VulkanLoad),
) !?vk.VkPhysicalDeviceDescriptorHeapFeaturesEXT {
    var sup = GetFnType(checkDescriptorHeaps){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_HEAP_FEATURES_EXT };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Descriptor Heaps", sup.descriptorHeap, &need.descriptorHeap);

    if (fullSup) {
        try enabledExts.append("VK_EXT_descriptor_heap");
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkWriteResourceDescriptorsEXT), .name = "vkWriteResourceDescriptorsEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkWriteSamplerDescriptorsEXT), .name = "vkWriteSamplerDescriptorsEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdBindResourceHeapEXT), .name = "vkCmdBindResourceHeapEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdBindSamplerHeapEXT), .name = "vkCmdBindSamplerHeapEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdPushDataEXT), .name = "vkCmdPushDataEXT" });
        return need;
    }
    return null;
}

fn checkDynamicState3(
    enabledExts: *std.array_list.Managed([*c]const u8),
    gpu: vk.VkPhysicalDevice,
    fnLoads: *std.array_list.Managed(VulkanLoad),
) !?vk.VkPhysicalDeviceExtendedDynamicState3FeaturesEXT {
    var sup = GetFnType(checkDynamicState3){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT };
    var need = @TypeOf(sup){ .sType = sup.sType };

    fillFeatureStruct(&sup, gpu);
    var fullSup = true;

    fullSup &= checkFeature("Polygon Mode", sup.extendedDynamicState3PolygonMode, &need.extendedDynamicState3PolygonMode);
    fullSup &= checkFeature("Raster Samples", sup.extendedDynamicState3RasterizationSamples, &need.extendedDynamicState3RasterizationSamples);
    fullSup &= checkFeature("Sample Mask", sup.extendedDynamicState3SampleMask, &need.extendedDynamicState3SampleMask);
    fullSup &= checkFeature("Depth Clamp", sup.extendedDynamicState3DepthClampEnable, &need.extendedDynamicState3DepthClampEnable);
    fullSup &= checkFeature("Color Blend", sup.extendedDynamicState3ColorBlendEnable, &need.extendedDynamicState3ColorBlendEnable);
    fullSup &= checkFeature("Color Blend Equation", sup.extendedDynamicState3ColorBlendEquation, &need.extendedDynamicState3ColorBlendEquation);
    fullSup &= checkFeature("Color Write Mask", sup.extendedDynamicState3ColorWriteMask, &need.extendedDynamicState3ColorWriteMask);
    fullSup &= checkFeature("Alpha to Coverage", sup.extendedDynamicState3AlphaToCoverageEnable, &need.extendedDynamicState3AlphaToCoverageEnable);
    fullSup &= checkFeature("Alpha to One", sup.extendedDynamicState3AlphaToOneEnable, &need.extendedDynamicState3AlphaToOneEnable);
    fullSup &= checkFeature("Conservative Raster", sup.extendedDynamicState3ConservativeRasterizationMode, &need.extendedDynamicState3ConservativeRasterizationMode);

    if (fullSup) {
        try enabledExts.append("VK_EXT_extended_dynamic_state3");
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetPolygonModeEXT), .name = "vkCmdSetPolygonModeEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetRasterizationSamplesEXT), .name = "vkCmdSetRasterizationSamplesEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetSampleMaskEXT), .name = "vkCmdSetSampleMaskEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetDepthClampEnableEXT), .name = "vkCmdSetDepthClampEnableEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetColorBlendEnableEXT), .name = "vkCmdSetColorBlendEnableEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetColorBlendEquationEXT), .name = "vkCmdSetColorBlendEquationEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetColorWriteMaskEXT), .name = "vkCmdSetColorWriteMaskEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetAlphaToOneEnableEXT), .name = "vkCmdSetAlphaToOneEnableEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetAlphaToCoverageEnableEXT), .name = "vkCmdSetAlphaToCoverageEnableEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetConservativeRasterizationModeEXT), .name = "vkCmdSetConservativeRasterizationModeEXT" });
        return need;
    }
    return null;
}

fn checkDynamicState2(
    enabledExts: *std.array_list.Managed([*c]const u8),
    gpu: vk.VkPhysicalDevice,
    fnLoads: *std.array_list.Managed(VulkanLoad),
) !?vk.VkPhysicalDeviceExtendedDynamicState2FeaturesEXT {
    var sup = GetFnType(checkDynamicState2){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Extended State 2", sup.extendedDynamicState2, &need.extendedDynamicState2);
    fullSup &= checkFeature("Extended State 2 Logic Op", sup.extendedDynamicState2LogicOp, &need.extendedDynamicState2LogicOp);
    fullSup &= checkFeature("Extended State 2 Patch Control", sup.extendedDynamicState2PatchControlPoints, &need.extendedDynamicState2PatchControlPoints);

    if (fullSup) {
        try enabledExts.append("VK_EXT_extended_dynamic_state2");
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetVertexInputEXT), .name = "vkCmdSetVertexInputEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetLogicOpEnableEXT), .name = "vkCmdSetLogicOpEnableEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetLogicOpEXT), .name = "vkCmdSetLogicOpEXT" });
        return need;
    }
    return null;
}

fn checkFragmentShadingRate(
    enabledExts: *std.array_list.Managed([*c]const u8),
    gpu: vk.VkPhysicalDevice,
    fnLoads: *std.array_list.Managed(VulkanLoad),
) !?vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR {
    var sup = GetFnType(checkFragmentShadingRate){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Pipeline Fragment Shading Rate", sup.pipelineFragmentShadingRate, &need.pipelineFragmentShadingRate);
    fullSup &= checkFeature("Primitive Fragment Shading Rate", sup.primitiveFragmentShadingRate, &need.primitiveFragmentShadingRate);
    fullSup &= checkFeature("Attachment Fragment Shading Rate", sup.attachmentFragmentShadingRate, &need.attachmentFragmentShadingRate);

    if (fullSup) {
        try enabledExts.append("VK_KHR_fragment_shading_rate");
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdSetFragmentShadingRateKHR), .name = "vkCmdSetFragmentShadingRateKHR" });
        return need;
    }
    return null;
}

fn checkShaderObjects(
    enabledExts: *std.array_list.Managed([*c]const u8),
    gpu: vk.VkPhysicalDevice,
    fnLoads: *std.array_list.Managed(VulkanLoad),
) !?vk.VkPhysicalDeviceShaderObjectFeaturesEXT {
    var sup = GetFnType(checkShaderObjects){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Shader Objects", sup.shaderObject, &need.shaderObject);

    if (fullSup) {
        try enabledExts.append("VK_EXT_shader_object");
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCreateShadersEXT), .name = "vkCreateShadersEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkDestroyShaderEXT), .name = "vkDestroyShaderEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdBindShadersEXT), .name = "vkCmdBindShadersEXT" });
        return need;
    }
    return null;
}

fn checkMeshShaders(
    enabledExts: *std.array_list.Managed([*c]const u8),
    gpu: vk.VkPhysicalDevice,
    fnLoads: *std.array_list.Managed(VulkanLoad),
) !?vk.VkPhysicalDeviceMeshShaderFeaturesEXT {
    var sup = GetFnType(checkMeshShaders){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Mesh Shaders", sup.meshShader, &need.meshShader);
    fullSup &= checkFeature("Task Shaders", sup.taskShader, &need.taskShader);
    fullSup &= checkFeature("Mesh Shader Queries", sup.meshShaderQueries, &need.meshShaderQueries);

    if (fullSup) {
        try enabledExts.append("VK_EXT_mesh_shader");
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdDrawMeshTasksEXT), .name = "vkCmdDrawMeshTasksEXT" });
        try fnLoads.append(.{ .functionPtr = @ptrCast(&vkFn.vkCmdDrawMeshTasksIndirectEXT), .name = "vkCmdDrawMeshTasksIndirectEXT" });
        return need;
    }
    return null;
}

fn checkVulkan11Features(gpu: vk.VkPhysicalDevice) !?vk.VkPhysicalDeviceVulkan11Features {
    var sup = GetFnType(checkVulkan11Features){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Shader Draw Parameters", sup.shaderDrawParameters, &need.shaderDrawParameters);
    fullSup &= checkFeature("Storage Buffer 16Bit Access", sup.storageBuffer16BitAccess, &need.storageBuffer16BitAccess);
    fullSup &= checkFeature("Uniform/Storage Buffer 16Bit Access", sup.uniformAndStorageBuffer16BitAccess, &need.uniformAndStorageBuffer16BitAccess);

    if (fullSup) {
        return need;
    }
    return null;
}

fn checkVulkan12Features(gpu: vk.VkPhysicalDevice) !?vk.VkPhysicalDeviceVulkan12Features {
    var sup = GetFnType(checkVulkan12Features){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Buffer Device Address", sup.bufferDeviceAddress, &need.bufferDeviceAddress);
    fullSup &= checkFeature("Descriptor Indexing", sup.descriptorIndexing, &need.descriptorIndexing);
    fullSup &= checkFeature("Desc-Bind StorageImg Update After Bind", sup.descriptorBindingStorageImageUpdateAfterBind, &need.descriptorBindingStorageImageUpdateAfterBind);
    fullSup &= checkFeature("Desc-Bind SampledImg Update After Bind", sup.descriptorBindingSampledImageUpdateAfterBind, &need.descriptorBindingSampledImageUpdateAfterBind);
    fullSup &= checkFeature("Descriptor Binding Partially Bound", sup.descriptorBindingPartiallyBound, &need.descriptorBindingPartiallyBound);
    fullSup &= checkFeature("Timeline Semaphores", sup.timelineSemaphore, &need.timelineSemaphore);
    fullSup &= checkFeature("Tunetime Descriptor Array", sup.runtimeDescriptorArray, &need.runtimeDescriptorArray);
    fullSup &= checkFeature("Shader StorageImg Array-NonUniform-Indexing", sup.shaderStorageImageArrayNonUniformIndexing, &need.shaderStorageImageArrayNonUniformIndexing);
    fullSup &= checkFeature("Shader SampledImg Array-NonUniform-Indexing", sup.shaderSampledImageArrayNonUniformIndexing, &need.shaderSampledImageArrayNonUniformIndexing);
    fullSup &= checkFeature("Shader Float 16", sup.shaderFloat16, &need.shaderFloat16);
    fullSup &= checkFeature("Shader Buffer Int64 Atomics", sup.shaderBufferInt64Atomics, &need.shaderBufferInt64Atomics);

    if (fullSup) {
        return need;
    }
    return null;
}

fn checkVulkan13Features(gpu: vk.VkPhysicalDevice) !?vk.VkPhysicalDeviceVulkan13Features {
    var sup = GetFnType(checkVulkan13Features){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Dynamic Rendering", sup.dynamicRendering, &need.dynamicRendering);
    fullSup &= checkFeature("Synchronization 2", sup.synchronization2, &need.synchronization2);
    fullSup &= checkFeature("Maintenance 4", sup.maintenance4, &need.maintenance4);

    if (fullSup) {
        return need;
    }
    return null;
}

fn checkMaintenance5Features(enabledExts: *std.array_list.Managed([*c]const u8), gpu: vk.VkPhysicalDevice) !?vk.VkPhysicalDeviceMaintenance5FeaturesKHR {
    var sup = GetFnType(checkMaintenance5Features){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_5_FEATURES_KHR };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Maintenance 5", sup.maintenance5, &need.maintenance5);

    if (fullSup) {
        try enabledExts.append("VK_KHR_maintenance5");
        return need;
    }
    return null;
}

fn checkDeviceFeatures2(gpu: vk.VkPhysicalDevice) !?vk.VkPhysicalDeviceFeatures2 {
    var sup = GetFnType(checkDeviceFeatures2){ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 };
    var need = @TypeOf(sup){ .sType = sup.sType };
    fillFeatureStruct(&sup, gpu);

    var fullSup = true;
    fullSup &= checkFeature("Shader Int 64", sup.features.shaderInt64, &need.features.shaderInt64);
    fullSup &= checkFeature("Wide Lines", sup.features.wideLines, &need.features.wideLines);
    fullSup &= checkFeature("Pipeline Statistics Query", sup.features.pipelineStatisticsQuery, &need.features.pipelineStatisticsQuery);

    if (fullSup) {
        return need;
    }
    return null;
}

// fn checkTEMPLATE(enabledExts: *std.array_list.Managed([*c]const u8), gpu: vk.VkPhysicalDevice) !?void {
//     var sup = getFnType(checkTEMPLATE){ .sType = void };
//     var need = @TypeOf(sup){ .sType = sup.sType };
//     fillFeatureStruct(&sup, gpu);

//     const fullSup = true;
//     fullSup &= checkFeature("", &sup, &need);

//     if (fullSup) {
//         try enabledExts.append("");
//         return need;
//     }
//     return null;
// }
