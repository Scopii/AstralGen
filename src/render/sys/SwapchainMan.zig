const RendererOutQueue = @import("../RendererOutQueue.zig").RendererOutQueue;
const TexId = @import("../types/res/TextureMeta.zig").TextureMeta.TexId;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const Window = @import("../../window/Window.zig").Window;
const rc = @import("../../.configs/renderConfig.zig");
const Context = @import("Context.zig").Context;
const sdl = @import("../../.modules/sdl.zig").c;
const vk = @import("../../.modules/vk.zig").c;
const vhF = @import("../help/Functions.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

pub const SwapchainMan = struct {
    alloc: Allocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,
    queueHandle: vk.VkQueue,
    instance: vk.VkInstance,
    swapchains: LinkedMap(Swapchain, rc.MAX_WINDOWS, u32, 32 + rc.MAX_WINDOWS, 0) = .{},
    targetIndices: SimpleMap(u32, rc.MAX_WINDOWS, u32, 32 + rc.MAX_WINDOWS, 0) = .{},
    hiddenSwapchains: LinkedMap(u8, rc.MAX_WINDOWS, u32, 32 + rc.MAX_WINDOWS, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context) !SwapchainMan {
        return .{
            .alloc = alloc,
            .gpi = context.gpi,
            .gpu = context.gpu,
            .queueHandle = context.graphicsQ.handle,
            .instance = context.instance,
        };
    }

    pub fn deinit(self: *SwapchainMan) void {
        for (self.swapchains.getItems()) |*swapchain| {
            swapchain.deinit(self.alloc, self.gpi, self.instance, .withSurface);
        }
    }

    pub fn updateTargets(self: *SwapchainMan, flightId: u8, activeWindows: []const Window) !void {
        self.targetIndices.clear();

        for (activeWindows) |*window| {
            const swapchain = self.swapchains.getPtrByKey(window.id.val);

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
                        std.debug.print("Could not Resolve Swapchain Error {} (ID {}) {}", .{ result2, window.id.val, swapchain.* });
                        continue;
                    } else std.debug.print("Resolved Error for Swapchain {} (ID {}) {}", .{ result2, window.id.val, swapchain.* });
                },
                else => try vhF.check(result1, "Could not acquire swapchain image with unknown error"),
            }

            swapchain.getCurTexture().state = .{ .layout = .Undefined, .stage = .ColorAtt, .access = .None }; // Transfer -> TopOfPipe or ColorAttachmentOutput?
            const mapIndex = self.swapchains.getIndexByKey(window.id.val);
            self.targetIndices.upsert(window.id.val, mapIndex);

            if (rc.SWAPCHAIN_PROFILING == true) {
                const end = std.time.microTimestamp();
                std.debug.print("Swapchain (ID {}) Acquire {d:.3} ms\n", .{ window.id.val, @as(f64, @floatFromInt(end - start)) / 1_000.0 });
            }
        }
    }

    pub fn getTargetsIndices(self: *SwapchainMan) []const u32 {
        return self.targetIndices.getConstItems();
    }

    pub fn getTargetByIndex(self: *SwapchainMan, swapchainIndex: u32) *Swapchain {
        return self.swapchains.getPtrByIndex(swapchainIndex);
    }

    pub fn getTargetIndex(self: *SwapchainMan, windowId: Window.WindowId) ?u32 {
        if (self.targetIndices.isKeyUsed(windowId.val) == true) return self.targetIndices.getByKey(windowId.val) else return null;
    }

    pub fn changeState(self: *SwapchainMan, windowId: Window.WindowId, inUse: bool) void {
        self.swapchains.getPtrByKey(windowId.val).inUse = inUse;
    }

    pub fn getMaxExtent(self: *SwapchainMan, texId: TexId) vk.VkExtent2D {
        var maxWidth: u32 = 1;
        var maxHeight: u32 = 1;

        for (self.swapchains.getItems()) |swapchain| {
            if (swapchain.renderTexId == texId) {
                maxWidth = @max(maxWidth, swapchain.extent.width);
                maxHeight = @max(maxHeight, swapchain.extent.height);
            }
            for (swapchain.linkedTexIds) |linkedId| {
                if (linkedId == null) break;
                if (linkedId == texId) {
                    maxWidth = @max(maxWidth, swapchain.extent.width);
                    maxHeight = @max(maxHeight, swapchain.extent.height);
                }
            }
        }
        return vk.VkExtent2D{ .width = maxWidth, .height = maxHeight };
    }

    pub fn createSwapchain(self: *SwapchainMan, window: Window, _: vk.VkCommandPool) !void {
        const surface = try createSurface(window.handle, self.instance);
        const swapchain = try Swapchain.init(self.alloc, self.gpi, surface, window.extent, self.gpu, window.renderTexId, window.linkedTexIds, null, window.id);
        self.hiddenSwapchains.upsert(window.id.val, rc.MAX_IN_FLIGHT);
        self.swapchains.upsert(window.id.val, swapchain);
        std.debug.print("Swapchain added to Window {}\n", .{window.id.val});
    }

    pub fn recreateSwapchain(self: *SwapchainMan, windowId: Window.WindowId, newExtent: vk.VkExtent2D, _: vk.VkCommandPool) !void {
        const swapchainPtr = self.swapchains.getPtrByKey(windowId.val);
        try swapchainPtr.recreate(self.alloc, self.gpi, self.gpu, self.instance, newExtent);
        self.hiddenSwapchains.upsert(windowId.val, rc.MAX_IN_FLIGHT);
        std.debug.print("Swapchain recreated\n", .{});
    }

    pub fn incrementHiddenSwapchains(self: *SwapchainMan, rendererOutQueue: *RendererOutQueue) void {
        const len = self.hiddenSwapchains.getLength(); // capture before
        var i: u32 = len;

        while (i > 0) {
            i -= 1;
            const framesLeft = self.hiddenSwapchains.getPtrByIndex(i);
            
            if (framesLeft.* == 0) {
                const windowId = self.hiddenSwapchains.getKeyByIndex(i);
                rendererOutQueue.append(.{ .framePresentedForWindow = .{ .val = windowId } });
                self.hiddenSwapchains.removeIndex(i);
            } else {
                framesLeft.* -= 1;
            }
        }
    }

    pub fn removeSwapchains(self: *SwapchainMan, windowId: Window.WindowId) void {
        if (self.swapchains.isKeyValid(windowId.val) == true) {
            const swapchain = self.swapchains.getPtrByKey(windowId.val);
            swapchain.deinit(self.alloc, self.gpi, self.instance, .withSurface);
            self.swapchains.remove(windowId.val);

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