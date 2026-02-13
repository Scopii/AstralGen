const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const TexId = @import("../types/res/TextureMeta.zig").TextureMeta.TexId;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const Window = @import("../../platform/Window.zig").Window;
const rc = @import("../../configs/renderConfig.zig");
const Context = @import("Context.zig").Context;
const sdl = @import("../../modules/sdl.zig").c;
const vk = @import("../../modules/vk.zig").c;
const vhF = @import("../help/Functions.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

pub const SwapchainMan = struct {
    alloc: Allocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,
    instance: vk.VkInstance,
    swapchains: CreateMapArray(Swapchain, rc.MAX_WINDOWS, u32, 32 + rc.MAX_WINDOWS, 0) = .{},
    targetPtrs: [rc.MAX_WINDOWS]*Swapchain = undefined,

    pub fn init(alloc: Allocator, context: *const Context) !SwapchainMan {
        return .{
            .alloc = alloc,
            .gpi = context.gpi,
            .gpu = context.gpu,
            .instance = context.instance,
        };
    }

    pub fn deinit(self: *SwapchainMan) void {
        for (self.swapchains.getElements()) |*swapchain| {
            swapchain.deinit(self.alloc, self.gpi, self.instance, .withSurface);
        }
    }

    pub fn getUpdatedTargets(self: *SwapchainMan, flightId: u8) ![]*Swapchain {
        var count: u8 = 0;

        for (0..self.swapchains.getCount()) |i| {
            const swapchain = self.swapchains.getPtrAtIndex(@intCast(i));
            if (swapchain.inUse == false) continue;

            const start = if (rc.SWAPCHAIN_PROFILING == true) std.time.microTimestamp() else 0;
            const result1 = swapchain.acquireNextImage(self.gpi, flightId);

            switch (result1) {
                vk.VK_SUCCESS => {},
                vk.VK_TIMEOUT, vk.VK_NOT_READY => {
                    std.debug.print("OS could not provide Swapchain Image in Time \n", .{});
                    continue;
                },
                vk.VK_ERROR_OUT_OF_DATE_KHR, vk.VK_SUBOPTIMAL_KHR => {
                    try swapchain.recreate(self.alloc, self.gpi, self.gpu, self.instance, swapchain.extent);
                    const result2 = swapchain.acquireNextImage(self.gpi, flightId);

                    if (result2 != vk.VK_SUCCESS) {
                        std.debug.print("Could not Resolve Swapchain Error {} (ID {}) {}", .{ result2, self.swapchains.getKeyFromIndex(@intCast(i)), swapchain.* });
                        continue;
                    } else std.debug.print("Resolved Error for Swapchain {} (ID {}) {}", .{ result2, self.swapchains.getKeyFromIndex(@intCast(i)), swapchain.* });
                },
                else => try vhF.check(result1, "Could not acquire swapchain image with unknown error"),
            }

            swapchain.getCurTexture().state = .{ .layout = .Undefined, .stage = .ColorAtt, .access = .None }; // Transfer -> TopOfPipe or ColorAttachmentOutput?
            self.targetPtrs[count] = swapchain;
            count += 1;

            if (rc.SWAPCHAIN_PROFILING == true) {
                const end = std.time.microTimestamp();
                std.debug.print("Swapchain (ID {}) Acquire {d:.3} ms\n", .{ self.swapchains.getKeyFromIndex(@intCast(i)), @as(f64, @floatFromInt(end - start)) / 1_000.0 });
            }
        }
        return self.targetPtrs[0..count];
    }

    pub fn changeState(self: *SwapchainMan, windowId: Window.WindowId, inUse: bool) void {
        self.swapchains.getPtr(windowId.val).inUse = inUse;
    }

    pub fn getMaxRenderExtent(self: *SwapchainMan, texId: TexId) vk.VkExtent2D {
        var maxWidth: u32 = 1;
        var maxHeight: u32 = 1;

        for (self.swapchains.getElements()) |swapchain| {
            if (swapchain.renderTexId == texId) {
                maxWidth = @max(maxWidth, swapchain.extent.width);
                maxHeight = @max(maxHeight, swapchain.extent.height);
            }
        }
        return vk.VkExtent2D{ .width = maxWidth, .height = maxHeight };
    }

    pub fn createSwapchain(self: *SwapchainMan, window: Window) !void {
        const surface = try createSurface(window.handle, self.instance);
        const swapchain = try Swapchain.init(self.alloc, self.gpi, surface, window.extent, self.gpu, window.renderTexId, null);
        self.swapchains.set(window.id.val, swapchain);
        std.debug.print("Swapchain added to Window {}\n", .{window.id.val});
    }

    pub fn recreateSwapchain(self: *SwapchainMan, windowId: Window.WindowId, newExtent: vk.VkExtent2D) !void {
        const swapchainPtr = self.swapchains.getPtr(windowId.val);
        try swapchainPtr.recreate(self.alloc, self.gpi, self.gpu, self.instance, newExtent);
        std.debug.print("Swapchain recreated\n", .{});
    }

    pub fn removeSwapchains(self: *SwapchainMan, windowId: Window.WindowId) void {
        if (self.swapchains.isKeyValid(windowId.val) == true) {
            const swapchain = self.swapchains.getPtr(windowId.val);
            swapchain.deinit(self.alloc, self.gpi, self.instance, .withSurface);
            self.swapchains.removeAtKey(windowId.val);

            std.debug.print("Swapchain Key {} destroyed\n", .{windowId.val});
        } else std.debug.print("Swapchain to destroy missing.\n", .{});
    }
};

fn createSurface(window: *sdl.SDL_Window, instance: vk.VkInstance) !vk.VkSurfaceKHR {
    var surface: vk.VkSurfaceKHR = undefined;
    if (sdl.SDL_Vulkan_CreateSurface(window, @ptrCast(instance), null, @ptrCast(&surface)) == false) {
        std.log.err("Unable to create Vulkan surface: {s}\n", .{sdl.SDL_GetError()});
        return error.VkSurface;
    }
    return surface;
}
