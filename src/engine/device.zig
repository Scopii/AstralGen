const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;

pub const DeviceInfo = struct {
    phys_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    queue_families: QueueFamilies,
};

pub fn createDevice(alloc: Allocator, instance: c.VkInstance, surface: c.VkSurfaceKHR) !DeviceInfo {
    const phys_device = try pickPhysicalDevice(alloc, instance);
    const queue_families = try checkDeviceQueueFamilies(alloc, surface, phys_device); // Only call once
    const device = try createLogicalDeviceWithFamilies(alloc, phys_device, queue_families);

    return DeviceInfo{
        .phys_device = phys_device,
        .device = device,
        .queue_families = queue_families,
    };
}

pub fn pickPhysicalDevice(alloc: Allocator, instance: c.VkInstance) !c.VkPhysicalDevice {
    var device_count: u32 = 0;
    const enum_device = c.vkEnumeratePhysicalDevices(instance, &device_count, null);

    if (enum_device != c.VK_SUCCESS) {
        std.log.err("Failed to enumerate devices. Reason {d}\n", .{enum_device});
        return error.EnumDevice;
    }

    if (device_count == 0) {
        std.log.err("No Vulkan devices found\n", .{});
        return error.NoDevice;
    }

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    const devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
    _ = c.vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr);

    var phys_device: ?c.VkPhysicalDevice = null;
    for (devices) |device| {
        if (checkDevice(device) and try checkDeviceFeatures(alloc, device)) {
            phys_device = device;
            break;
        }
    }

    if (phys_device == null) {
        std.log.err("No suitable Vulkan device found\n", .{});
        return error.NoDevice;
    }

    return phys_device.?;
}

pub fn checkDevice(device: c.VkPhysicalDevice) bool {
    var properties: c.VkPhysicalDeviceProperties = undefined;
    c.vkGetPhysicalDeviceProperties(device, &properties);

    var features: c.VkPhysicalDeviceFeatures = undefined;
    c.vkGetPhysicalDeviceFeatures(device, &features);

    std.debug.print("Checking Device: {s}\n", .{properties.deviceName});

    if (properties.deviceType != c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
        std.debug.print("Device not a discrete GPU\n", .{});
        return false;
    }

    return true;
}

pub fn checkDeviceFeatures(alloc: Allocator, phys_device: c.VkPhysicalDevice) !bool {
    var extensions: u32 = 0;
    const count = c.vkEnumerateDeviceExtensionProperties(phys_device, null, &extensions, null);

    if (count != c.VK_SUCCESS) {
        std.log.err("Failed to enumerate device extensions. Reason {d}\n", .{count});
        return error.DeviceExtension;
    }

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    const available_extensions = try allocator.alloc(c.VkExtensionProperties, extensions);
    const result = c.vkEnumerateDeviceExtensionProperties(phys_device, null, &extensions, available_extensions.ptr);
    if (result != c.VK_SUCCESS) {
        std.log.err("Failed to get device extensions. Reason {d}\n", .{result});
        return error.DeviceExtension;
    }

    const required_extensions = [_][]const u8{ "VK_KHR_swapchain", "VK_KHR_synchronization2" };

    var match_extensions: u32 = 0;

    for (available_extensions) |extension| {
        for (required_extensions) |required_extension| {
            const ext_name: [*c]const u8 = @ptrCast(extension.extensionName[0..]);

            const match = std.mem.eql(u8, required_extension, std.mem.span(ext_name));
            if (match) {
                match_extensions += 1;
                break;
            }
        }
    }

    return match_extensions == required_extensions.len;
}

pub const QueueFamilies = struct {
    graphics: u32,
    present: u32,
};

pub fn checkDeviceQueueFamilies(alloc: Allocator, surface: c.VkSurfaceKHR, phys_device: c.VkPhysicalDevice) !QueueFamilies {
    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(phys_device, &queue_family_count, null);

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
    c.vkGetPhysicalDeviceQueueFamilyProperties(phys_device, &queue_family_count, queue_families.ptr);

    var graphics_family: ?usize = null;
    var present_family: ?usize = null;
    for (queue_families, 0..) |family, index| {
        if (family.queueCount > 0 and family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            graphics_family = index;
        }

        var present_support: c.VkBool32 = c.VK_FALSE;
        const result = c.vkGetPhysicalDeviceSurfaceSupportKHR(phys_device, @intCast(index), surface, &present_support);
        if (result != c.VK_SUCCESS) {
            std.log.warn("No present support found ! Reason {d}\n", .{result});
        }

        if (family.queueCount > 0 and present_support == c.VK_TRUE) {
            present_family = index;
        }

        if (graphics_family != null and present_family != null) {
            break;
        }
    }

    const family_indices = QueueFamilies{
        .graphics = @intCast(graphics_family.?),
        .present = @intCast(present_family.?),
    };

    return family_indices;
}

pub fn createLogicalDeviceWithFamilies(alloc: Allocator, phys_device: c.VkPhysicalDevice, families: QueueFamilies) !c.VkDevice {
    var priority: f32 = 1.0;

    var queue_infos = std.ArrayList(c.VkDeviceQueueCreateInfo).init(alloc);
    defer queue_infos.deinit();

    const graphics_queue_info = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = families.graphics,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    };

    try queue_infos.append(graphics_queue_info);

    if (families.graphics != families.present) {
        const present_qeueu_create_info = c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = families.present,
            .queueCount = 1,
            .pQueuePriorities = &priority,
        };

        try queue_infos.append(present_qeueu_create_info);
    }

    // Enable required device extensions
    const device_extensions = [_][*c]const u8{ "VK_KHR_swapchain", "VK_KHR_synchronization2", "VK_KHR_dynamic_rendering" };

    var features: c.VkPhysicalDeviceFeatures = undefined;
    c.vkGetPhysicalDeviceFeatures(phys_device, &features);

    const dynamic_rendering = c.VkPhysicalDeviceDynamicRenderingFeatures{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
        .pNext = null,
        .dynamicRendering = c.VK_TRUE,
    };

    const createInfo = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &dynamic_rendering, // Add missing field
        .flags = 0, // Add missing field
        .pQueueCreateInfos = queue_infos.items.ptr,
        .queueCreateInfoCount = @intCast(queue_infos.items.len),
        .pEnabledFeatures = &features,
        .enabledExtensionCount = device_extensions.len, // Enable extensions
        .ppEnabledExtensionNames = &device_extensions, // Point to extension array
        .enabledLayerCount = 0, // Add missing field
        .ppEnabledLayerNames = null, // Add missing field
    };

    var device: c.VkDevice = undefined;
    const result = c.vkCreateDevice(phys_device, &createInfo, null, &device);
    if (result != c.VK_SUCCESS) {
        std.log.err("Unable to create Vulkan device! Reason {d}\n", .{result});
        return error.DeviceCreation;
    }

    return device;
}
