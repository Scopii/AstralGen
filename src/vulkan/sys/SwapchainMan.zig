const TexId = @import("../types/res/TextureMeta.zig").TextureMeta.TexId;
const LinkedMap = @import("../../structures/LinkedMap.zig").LinkedMap;
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
    queueHandle: vk.VkQueue,
    instance: vk.VkInstance,
    swapchains: LinkedMap(Swapchain, rc.MAX_WINDOWS, u32, 32 + rc.MAX_WINDOWS, 0) = .{},
    targetPtrs: [rc.MAX_WINDOWS]*Swapchain = undefined,

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

    pub fn getUpdatedTargets(self: *SwapchainMan, flightId: u8) ![]*Swapchain {
        var count: u8 = 0;

        for (0..self.swapchains.getLength()) |i| {
            const swapchain = self.swapchains.getPtrByIndex(@intCast(i));
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
                        std.debug.print("Could not Resolve Swapchain Error {} (ID {}) {}", .{ result2, self.swapchains.getKeyByIndex(@intCast(i)), swapchain.* });
                        continue;
                    } else std.debug.print("Resolved Error for Swapchain {} (ID {}) {}", .{ result2, self.swapchains.getKeyByIndex(@intCast(i)), swapchain.* });
                },
                else => try vhF.check(result1, "Could not acquire swapchain image with unknown error"),
            }

            swapchain.getCurTexture().state = .{ .layout = .Undefined, .stage = .ColorAtt, .access = .None }; // Transfer -> TopOfPipe or ColorAttachmentOutput?
            self.targetPtrs[count] = swapchain;
            count += 1;

            if (rc.SWAPCHAIN_PROFILING == true) {
                const end = std.time.microTimestamp();
                std.debug.print("Swapchain (ID {}) Acquire {d:.3} ms\n", .{ self.swapchains.getKeyByIndex(@intCast(i)), @as(f64, @floatFromInt(end - start)) / 1_000.0 });
            }
        }
        return self.targetPtrs[0..count];
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
        const swapchain = try Swapchain.init(self.alloc, self.gpi, surface, window.extent, self.gpu, window.renderTexId, window.linkedTexIds, null, window.id.val);
        //try clearSwapchainImages(self.gpi, self.queueHandle, cmdPool, &swapchain);
        self.swapchains.upsert(window.id.val, swapchain);
        std.debug.print("Swapchain added to Window {}\n", .{window.id.val});
    }

    pub fn recreateSwapchain(self: *SwapchainMan, windowId: Window.WindowId, newExtent: vk.VkExtent2D, _: vk.VkCommandPool) !void {
        const swapchainPtr = self.swapchains.getPtrByKey(windowId.val);
        try swapchainPtr.recreate(self.alloc, self.gpi, self.gpu, self.instance, newExtent);
        //try clearSwapchainImages(self.gpi, self.queueHandle, cmdPool, swapchainPtr);
        std.debug.print("Swapchain recreated\n", .{});
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

fn clearSwapchainImages(device: vk.VkDevice, graphicsQueue: vk.VkQueue, cmdPool: vk.VkCommandPool, swapchain: *const Swapchain) !void {
    // Allocate One-Shot Command Buffer
    const allocInf = vk.VkCommandBufferAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandPool = cmdPool,
        .commandBufferCount = 1,
    };
    var cmd: vk.VkCommandBuffer = undefined;
    try vhF.check(vk.vkAllocateCommandBuffers(device, &allocInf, &cmd), "Failed alloc clear cmd");

    const beginInf = vk.VkCommandBufferBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try vhF.check(vk.vkBeginCommandBuffer(cmd, &beginInf), "Failed begin clear cmd");

    const clearColor = vk.VkClearColorValue{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } };
    const subRange = vhF.createSubresourceRange(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1);

    // Record Barriers and Clears
    for (swapchain.textures) |*tex| {
        const toTransfer = tex.createImageBarrier(.{ .stage = .TopOfPipe, .access = .None, .layout = .Undefined }, swapchain.subRange);
        const dep1 = vk.VkDependencyInfo{ .sType = vk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO, .imageMemoryBarrierCount = 1, .pImageMemoryBarriers = &toTransfer };
        vk.vkCmdPipelineBarrier2(cmd, &dep1);

        vk.vkCmdClearColorImage(cmd, tex.img, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &clearColor, 1, &subRange);

        const toBlit = tex.createImageBarrier(.{ .stage = .Clear, .access = .None, .layout = undefined }, swapchain.subRange);
        const dep2 = vk.VkDependencyInfo{ .sType = vk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO, .imageMemoryBarrierCount = 1, .pImageMemoryBarriers = &toBlit };
        vk.vkCmdPipelineBarrier2(cmd, &dep2);
    }

    try vhF.check(vk.vkEndCommandBuffer(cmd), "Failed end clear cmd");

    // Submit and Wait
    const submitInfo = vk.VkSubmitInfo{ .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cmd };
    try vhF.check(vk.vkQueueSubmit(graphicsQueue, 1, &submitInfo, null), "Failed submit clear");
    try vhF.check(vk.vkQueueWaitIdle(graphicsQueue), "Queue wait idle failed");

    vk.vkFreeCommandBuffers(device, cmdPool, 1, &cmd);
}
