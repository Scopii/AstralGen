const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const sdl = @import("../modules/sdl.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const Window = @import("../platform/Window.zig").Window;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const FixedList = @import("../structures/FixedList.zig").FixedList;
const vh = @import("Helpers.zig");
const createSemaphore = @import("Scheduler.zig").createSemaphore;
const rc = @import("../configs/renderConfig.zig");
const TextureBase = @import("resources/Texture.zig").TextureBase;
const TexId = @import("resources/Texture.zig").Texture.TexId;
const Swapchain = @import("Swapchain.zig").Swapchain;

pub const SwapchainMap = CreateMapArray(Swapchain, rc.MAX_WINDOWS, u32, rc.MAX_WINDOWS, 0);

pub const SwapchainManager = struct {
    alloc: Allocator,
    gpi: vk.VkDevice,
    instance: vk.VkInstance,
    swapchains: SwapchainMap = .{},
    targets: FixedList(u32, rc.MAX_WINDOWS) = .{},

    pub fn init(alloc: Allocator, context: *const Context) !SwapchainManager {
        return .{
            .alloc = alloc,
            .gpi = context.gpi,
            .instance = context.instance,
        };
    }

    pub fn deinit(self: *SwapchainManager) void {
        for (self.swapchains.getElements()) |*swapchain| {
            swapchain.deinit(self.alloc, self.gpi,self.instance,  .withSurface);
        }
    }

    pub fn getTargets(self: *SwapchainManager) []u32 {
        return self.targets.slice();
    }

    pub fn present(self: *SwapchainManager, presentIds: []const u32, presentQueue: vk.VkQueue) !void {
        var handles: [rc.MAX_WINDOWS]vk.VkSwapchainKHR = undefined;
        var imgIndices: [rc.MAX_WINDOWS]u32 = undefined;
        var waitSems: [rc.MAX_WINDOWS]vk.VkSemaphore = undefined;

        for (presentIds, 0..) |id, i| {
            const swapchain = self.swapchains.getAtIndex(id);
            handles[i] = swapchain.handle;
            imgIndices[i] = swapchain.curIndex;
            waitSems[i] = swapchain.renderDoneSems[swapchain.curIndex];
        }
        const presentInf = vk.VkPresentInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = @intCast(presentIds.len),
            .pWaitSemaphores = &waitSems,
            .swapchainCount = @intCast(presentIds.len),
            .pSwapchains = &handles,
            .pImageIndices = &imgIndices,
        };

        const result = vk.vkQueuePresentKHR(presentQueue, &presentInf);
        if (result != vk.VK_SUCCESS and result != vk.VK_ERROR_OUT_OF_DATE_KHR and result != vk.VK_SUBOPTIMAL_KHR) {
            try vh.check(result, "Failed to present swapchain image");
        }
    }

    pub fn updateTargets(self: *SwapchainManager, frameInFlight: u8, context: *Context) !bool {
        self.targets.clear();
        const gpi = self.gpi;

        for (0..self.swapchains.getCount()) |i| {
            const ptr = self.swapchains.getPtrAtIndex(@intCast(i));
            if (ptr.*.inUse == false) continue;

            const windowID = self.swapchains.getKeyFromIndex(@intCast(i));
            const result1 = vk.vkAcquireNextImageKHR(gpi, ptr.handle, 0, ptr.imgRdySems[frameInFlight], null, &ptr.curIndex);

            switch (result1) {
                vk.VK_SUCCESS => try self.targets.append(@intCast(i)),

                vk.VK_TIMEOUT, vk.VK_NOT_READY => {
                    std.debug.print("OS could not provide Swapchain Image in Time \n", .{});
                    continue;
                },

                vk.VK_ERROR_OUT_OF_DATE_KHR, vk.VK_SUBOPTIMAL_KHR => {
                    try self.createSwapchain(context, .{ .id = windowID });
                    const result2 = vk.vkAcquireNextImageKHR(gpi, ptr.handle, 0, ptr.imgRdySems[frameInFlight], null, &ptr.curIndex);

                    if (result2 == vk.VK_SUCCESS) {
                        try self.targets.append(@intCast(i));
                        std.debug.print("Resolved Error for Swapchain {}", .{ptr.*});
                    } else std.debug.print("Could not Resolve Swapchain Error {}", .{ptr.*});
                },
                else => try vh.check(result1, "Could not acquire swapchain image"),
            }
        }
        return if (self.targets.len != 0) true else false;
    }

    pub fn changeState(self: *SwapchainManager, winId: Window.WindowId, inUse: bool) void {
        self.swapchains.getPtr(winId.val).inUse = inUse;
    }

    pub fn getMaxRenderExtent(self: *SwapchainManager, texId: TexId) vk.VkExtent2D {
        var maxWidth: u32 = 0;
        var maxHeight: u32 = 0;

        for (self.swapchains.getElements()) |swapchain| {
            if (swapchain.inUse == true and swapchain.renderTexId == texId) {
                maxWidth = @max(maxWidth, swapchain.extent.width);
                maxHeight = @max(maxHeight, swapchain.extent.height);
            }
        }
        return vk.VkExtent2D{ .width = maxWidth, .height = maxHeight };
    }

    pub fn removeSwapchain(self: *SwapchainManager, windows: []const Window) void {
        for (windows) |window| {
            const key = window.id.val;

            if (self.swapchains.isKeyValid(key) == true) {
                // self.destroySwapchain(self.swapchains.getPtr(key), .withSurface);
                const swapchain = self.swapchains.getPtr(key);
                swapchain.deinit(self.alloc, self.gpi,self.instance,  .withSurface);
                self.swapchains.removeAtKey(key);

                std.debug.print("Swapchain Key {} destroyed\n", .{key});
            } else std.debug.print("Cant Swapchain to destroy missing.\n", .{});
        }
    }


    pub fn createSwapchain(self: *SwapchainManager, context: *const Context, input: union(enum) { window: Window, id: u32 }) !void {
        const alloc = self.alloc;
        const gpu = context.gpu;
        const gpi = context.gpi;
        var extent: vk.VkExtent2D = undefined;
        var ptr: *Swapchain = undefined;

        switch (input) {
            .window => |window| if (window.state == .needCreation) {
                extent = window.extent;
                const surface = try createSurface(window.handle, self.instance);
                const caps = try getSurfaceCaps(gpu, surface);
                const surfaceFormat = try pickSurfaceFormat(alloc, gpu, surface);

                const swapchain = try Swapchain.init(alloc, gpi, surfaceFormat, surface, extent, caps, window.renderTexId, null);
                self.swapchains.set(window.id.val, swapchain);
                std.debug.print("Swapchain added to Window {}\n", .{window.id.val});
                return;
            } else {
                ptr = self.swapchains.getPtr(window.id.val);
                extent = window.extent;
                std.debug.print("Swapchain recreated\n", .{});
            },
            .id => |windowId| {
                ptr = self.swapchains.getPtr(windowId);
                extent = ptr.extent;
                std.debug.print("Swapchain Error resolved\n", .{});
            },
        }

        const surface = ptr.surface;
        const caps = try getSurfaceCaps(gpu, surface);
        const surfaceFormat = try pickSurfaceFormat(alloc, gpu, surface);
        const swapchain = try Swapchain.init(alloc, gpi, surfaceFormat, surface, extent, caps, ptr.renderTexId, ptr.handle);
        ptr.deinit(self.alloc, self.gpi,self.instance,  .withoutSurface);
        ptr.* = swapchain;
    }
};

fn getSurfaceCaps(gpu: vk.VkPhysicalDevice, surface: vk.VkSurfaceKHR) !vk.VkSurfaceCapabilitiesKHR {
    var caps: vk.VkSurfaceCapabilitiesKHR = undefined;
    try vh.check(vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &caps), "Failed to get surface capabilities");
    return caps;
}

fn createSurface(window: *sdl.SDL_Window, instance: vk.VkInstance) !vk.VkSurfaceKHR {
    var surface: vk.VkSurfaceKHR = undefined;
    if (sdl.SDL_Vulkan_CreateSurface(window, @ptrCast(instance), null, @ptrCast(&surface)) == false) {
        std.log.err("Unable to create Vulkan surface: {s}\n", .{sdl.SDL_GetError()});
        return error.VkSurface;
    }
    return surface;
}

fn pickSurfaceFormat(alloc: Allocator, gpu: vk.VkPhysicalDevice, surface: vk.VkSurfaceKHR) !vk.VkSurfaceFormatKHR {
    var formatCount: u32 = 0;
    try vh.check(vk.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, null), "Failed to get format count");
    if (formatCount == 0) return error.NoSurfaceFormats;

    const formats = try alloc.alloc(vk.VkSurfaceFormatKHR, formatCount);
    defer alloc.free(formats);

    try vh.check(vk.vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, formats.ptr), "Failed to get surface formats");
    // Return preferred format if available otherwise first one
    if (formats.len == 1 and formats[0].format == vk.VK_FORMAT_UNDEFINED) {
        return vk.VkSurfaceFormatKHR{ .format = vk.VK_FORMAT_B8G8R8A8_UNORM, .colorSpace = vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR };
    }

    for (formats) |format| {
        if (format.format == vk.VK_FORMAT_B8G8R8A8_UNORM and format.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) return format;
    }
    return formats[0];
}
