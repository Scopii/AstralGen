const std = @import("std");
const c = @import("../../c.zig");
const check = @import("../error.zig").check;
const Allocator = std.mem.Allocator;

pub const Context = struct {
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, debugToggle: bool) !Context {
        const instance = try createInstance(alloc, debugToggle);
        return .{
            .instance = instance,
            .surface = try createSurface(window, instance),
        };
    }

    pub fn deinit(self: *Context) void {
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};

fn createSurface(window: *c.SDL_Window, instance: c.VkInstance) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    if (c.SDL_Vulkan_CreateSurface(window, @ptrCast(instance), null, @ptrCast(&surface)) == false) {
        std.log.err("Unable to create Vulkan surface: {s}\n", .{c.SDL_GetError()});
        return error.VkSurface;
    }
    return surface;
}

fn createInstance(alloc: Allocator, debugToggle: bool) !c.VkInstance {
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
