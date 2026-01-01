const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const rc = @import("../configs/renderConfig.zig");
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const Resource = @import("resources/Resource.zig").Resource;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const PushConstants = @import("resources/Resource.zig").PushConstants;
const SwapchainManager = @import("SwapchainManager.zig");
const Command = @import("Command.zig").Command;
const vh = @import("Helpers.zig");
const RendererData = @import("../App.zig").RendererData;

pub const ResourceState = struct {
    stage: vh.PipeStage = .TopOfPipe,
    access: vh.PipeAccess = .None,
    layout: vh.ImageLayout = .Undefined,
};

pub const RenderGraph = struct {
    alloc: Allocator,
    pipeLayout: vk.VkPipelineLayout,
    tempImgBarriers: std.array_list.Managed(vk.VkImageMemoryBarrier2),
    tempBufBarriers: std.array_list.Managed(vk.VkBufferMemoryBarrier2),

    pub fn init(alloc: Allocator, resourceMan: *const ResourceManager) !RenderGraph {
        return .{
            .alloc = alloc,
            .pipeLayout = resourceMan.descMan.pipeLayout,
            .tempImgBarriers = try std.array_list.Managed(vk.VkImageMemoryBarrier2).initCapacity(alloc, 30),
            .tempBufBarriers = try std.array_list.Managed(vk.VkBufferMemoryBarrier2).initCapacity(alloc, 30),
        };
    }

    pub fn deinit(self: *RenderGraph) void {
        self.tempImgBarriers.deinit();
        self.tempBufBarriers.deinit();
    }

    pub fn recordTransfers(self: *RenderGraph, cmd: *const Command, resMan: *ResourceManager) !void {
        if (resMan.pendingTransfers.items.len == 0) return;

        for (resMan.pendingTransfers.items) |transfer| {
            const dstResource = try resMan.getResourcePtr(transfer.dstResId);
            try self.createBarrierIfNeeded(dstResource.state, .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst }, dstResource);
            cmd.copyBuffer(resMan.stagingBuffer.buffer, &transfer, dstResource.resourceType.gpuBuf.buffer);
        }
        self.bakeBarriers(cmd);
    }

    fn createBarrierIfNeeded(self: *RenderGraph, state: ResourceState, neededState: ResourceState, resource: *Resource) !void {
        if (state.stage == neededState.stage and state.access == neededState.access and state.layout == neededState.layout) return;

        switch (resource.resourceType) {
            .gpuImg => |*gpuImg| {
                const barrier = createImageBarrier(state, neededState, gpuImg.img, gpuImg.imgInf.imgType);
                try self.tempImgBarriers.append(barrier);
                resource.state = neededState;
            },
            .gpuBuf => |*gpuBuf| {
                const barrier = createBufferBarrier(state, neededState, gpuBuf.buffer);
                try self.tempBufBarriers.append(barrier);
                resource.state = neededState;
            },
        }
    }

    pub fn recordPassBarriers(self: *RenderGraph, cmd: *const Command, pass: rc.Pass, resMan: *ResourceManager) !void {
        cmd.setGraphicsState();

        switch (pass.kind) {
            .graphics,
            => |graphics| {
                for (graphics.colorAtts) |attUsage| {
                    const resource = try resMan.getResourcePtr(attUsage.id);
                    try self.createBarrierIfNeeded(resource.state, attUsage.getNeededState(), resource);
                }
                if (graphics.depthAtt) |attUsage| {
                    const resource = try resMan.getResourcePtr(attUsage.id);
                    try self.createBarrierIfNeeded(resource.state, attUsage.getNeededState(), resource);
                }
                if (graphics.stencilAtt) |attUsage| {
                    const resource = try resMan.getResourcePtr(attUsage.id);
                    try self.createBarrierIfNeeded(resource.state, attUsage.getNeededState(), resource);
                }
            },

            .taskOrMesh => |taskOrMesh| {
                for (taskOrMesh.colorAtts) |attUsage| {
                    const resource = try resMan.getResourcePtr(attUsage.id);
                    try self.createBarrierIfNeeded(resource.state, attUsage.getNeededState(), resource);
                }
                if (taskOrMesh.depthAtt) |attUsage| {
                    const resource = try resMan.getResourcePtr(attUsage.id);
                    try self.createBarrierIfNeeded(resource.state, attUsage.getNeededState(), resource);
                }
                if (taskOrMesh.stencilAtt) |attUsage| {
                    const resource = try resMan.getResourcePtr(attUsage.id);
                    try self.createBarrierIfNeeded(resource.state, attUsage.getNeededState(), resource);
                }
            },
            else => {},
        }

        for (pass.resUsages) |resUsage| {
            const resource = try resMan.getResourcePtr(resUsage.id);
            try self.createBarrierIfNeeded(resource.state, resUsage.getNeededState(), resource);
        }

        for (pass.shaderUsages) |resUsage| {
            const resource = try resMan.getResourcePtr(resUsage.id);
            try self.createBarrierIfNeeded(resource.state, resUsage.getNeededState(), resource);
        }

        self.bakeBarriers(cmd);
    }

    fn recordCompute(cmd: *const Command, dispatch: rc.Pass.Dispatch, renderImgId: ?u32, resMan: *ResourceManager) !void {
        if (renderImgId) |imgId| {
            const resource = try resMan.getResourcePtr(imgId);
            switch (resource.resourceType) {
                .gpuImg => |gpuImg| {
                    cmd.dispatch(
                        (gpuImg.imgInf.extent.width + dispatch.x - 1) / dispatch.x,
                        (gpuImg.imgInf.extent.height + dispatch.y - 1) / dispatch.y,
                        1, // (gpuImg.imgInf.extent.depth + dispatch.z - 1) / dispatch.z
                    );
                },
                else => return error.ComputePassRenderImgIsNoImg,
            }
        } else cmd.dispatch(dispatch.x, dispatch.y, dispatch.z);
    }

    pub fn recordPass(self: *RenderGraph, cmd: *const Command, pass: rc.Pass, rendererData: RendererData, validShaders: []const ShaderObject, resMan: *ResourceManager) !void {
        try self.recordPassBarriers(cmd, pass, resMan);

        var pcs = PushConstants{ .runTime = rendererData.runTime, .deltaTime = rendererData.deltaTime };
        if (pass.shaderUsages.len > pcs.resourceSlots.len) return error.TooManyShaderSlotsInPass;
        // Assign Shader Slots
        for (0..pass.shaderUsages.len) |i| {
            const shaderSlot = pass.shaderUsages[i];
            const resource = try resMan.getResourcePtr(shaderSlot.id);
            pcs.resourceSlots[i] = resource.getResourceSlot();
        }

        const mainImg = switch (pass.kind) {
            .compute => null,
            .computeOnImage => |compOnImage| try resMan.getImagePtr(compOnImage.renderImgId),
            .graphics => |graphics| try resMan.getImagePtr(graphics.renderImgId),
            .taskOrMesh => |taskOrMesh| try resMan.getImagePtr(taskOrMesh.renderImgId),
        };

        if (mainImg) |img| {
            pcs.width = img.imgInf.extent.width;
            pcs.height = img.imgInf.extent.height;
        }

        cmd.setPushConstants(self.pipeLayout, vk.VK_SHADER_STAGE_ALL, 0, @sizeOf(PushConstants), &pcs);
        cmd.bindShaders(validShaders);

        switch (pass.kind) {
            .compute => |comp| try recordCompute(cmd, comp.workgroups, null, resMan),
            .computeOnImage => |compOnImage| try recordCompute(cmd, compOnImage.workgroups, compOnImage.renderImgId, resMan),
            .graphics => |graphics| try recordGraphics(cmd, graphics.colorAtts, graphics.depthAtt, graphics.stencilAtt, pcs.width, pcs.height, pass, resMan),
            .taskOrMesh => |taskOrMesh| try recordGraphics(cmd, taskOrMesh.colorAtts, taskOrMesh.depthAtt, taskOrMesh.stencilAtt, pcs.width, pcs.height, pass, resMan),
        }
    }

    fn recordGraphics(
        cmd: *const Command,
        colorAtts: []const rc.Pass.AttachmentUsage,
        depthAtt: ?rc.Pass.AttachmentUsage,
        stencilAtt: ?rc.Pass.AttachmentUsage,
        width: u32,
        height: u32,
        pass: rc.Pass,
        resMan: *ResourceManager,
    ) !void {
        if (colorAtts.len > 8) return error.TooManyAttachments;

        const depthInf: ?vk.VkRenderingAttachmentInfo = if (depthAtt) |depth| blk: {
            const img = try resMan.getImagePtr(depth.id);
            break :blk createAttachment(img.imgInf.imgType, img.view, depth.clear);
        } else null;

        const stencilInf: ?vk.VkRenderingAttachmentInfo = if (stencilAtt) |stencil| blk: {
            const img = try resMan.getImagePtr(stencil.id);
            break :blk createAttachment(img.imgInf.imgType, img.view, stencil.clear);
        } else null;

        var colorInfs: [8]vk.VkRenderingAttachmentInfo = undefined;
        for (0..colorAtts.len) |i| {
            const color = colorAtts[i];
            const img = try resMan.getImagePtr(color.id);
            colorInfs[i] = createAttachment(img.imgInf.imgType, img.view, color.clear);
        }

        cmd.beginRendering(width, height, colorInfs[0..colorAtts.len], depthInf, stencilInf);

        switch (pass.kind) {
            .compute, .computeOnImage => return error.ComputeLandedInGraphicsPass,
            .taskOrMesh => |taskOrMesh| cmd.drawMeshTasks(taskOrMesh.workgroups.x, taskOrMesh.workgroups.y, taskOrMesh.workgroups.z),
            .graphics => |graphics| {
                cmd.setEmptyVertexInput();
                cmd.draw(graphics.vertexCount, graphics.instanceCount, 0, 0);
            },
        }
        cmd.endRendering();
    }

    pub fn recordSwapchainBlits(self: *RenderGraph, cmd: *const Command, targets: []const u32, swapchainMap: *SwapchainManager.SwapchainMap, resMan: *ResourceManager) !void {
        const swapchainMidState = ResourceState{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst };
        // Render Image and Swapchain Preperations
        for (targets) |swapchainIndex| {
            const swapchain = swapchainMap.getPtrAtIndex(swapchainIndex);
            const renderImg = try resMan.getResourcePtr(swapchain.passImgId);
            try self.createBarrierIfNeeded(renderImg.state, .{ .stage = .Transfer, .access = .TransferRead, .layout = .TransferSrc }, renderImg);
            const swapchainImg = swapchain.images[swapchain.curIndex];
            try self.tempImgBarriers.append(createImageBarrier(.{}, swapchainMidState, swapchainImg, .Color));
        }
        self.bakeBarriers(cmd);

        // Blits
        for (targets) |swapchainIndex| {
            const swapchain = swapchainMap.getPtrAtIndex(swapchainIndex);
            const swapchainExtent = vk.VkExtent3D{ .height = swapchain.extent.height, .width = swapchain.extent.width, .depth = 1 };
            const renderImg = try resMan.getImagePtr(swapchain.passImgId);
            cmd.copyImageToImage(renderImg.img, renderImg.imgInf.extent, swapchain.images[swapchain.curIndex], swapchainExtent, rc.RENDER_IMG_STRETCH);
        }

        // Swapchain Presentation Barriers
        for (targets) |swapchainIndex| {
            const swapchain = swapchainMap.getPtrAtIndex(swapchainIndex);
            const presentState = ResourceState{ .stage = .BotOfPipe, .access = .None, .layout = .PresentSrc };
            try self.tempImgBarriers.append(createImageBarrier(swapchainMidState, presentState, swapchain.images[swapchain.curIndex], .Color));
        }
        self.bakeBarriers(cmd);
    }

    fn bakeBarriers(self: *RenderGraph, cmd: *const Command) void {
        cmd.bakeBarriers(self.tempImgBarriers.items, self.tempBufBarriers.items);
        self.tempImgBarriers.clearRetainingCapacity();
        self.tempBufBarriers.clearRetainingCapacity();
    }
};

fn createImageBarrier(curState: ResourceState, newState: ResourceState, img: vk.VkImage, imgType: vh.ImgType) vk.VkImageMemoryBarrier2 {
    const aspectMask: vk.VkImageAspectFlagBits = switch (imgType) {
        .Color => vk.VK_IMAGE_ASPECT_COLOR_BIT,
        .Depth => vk.VK_IMAGE_ASPECT_DEPTH_BIT,
        .Stencil => vk.VK_IMAGE_ASPECT_STENCIL_BIT,
    };

    return vk.VkImageMemoryBarrier2{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = @intFromEnum(curState.stage),
        .srcAccessMask = @intFromEnum(curState.access),
        .dstStageMask = @intFromEnum(newState.stage),
        .dstAccessMask = @intFromEnum(newState.access),
        .oldLayout = @intFromEnum(curState.layout),
        .newLayout = @intFromEnum(newState.layout),
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = img,
        .subresourceRange = createSubresourceRange(aspectMask, 0, 1, 0, 1),
    };
}

fn createBufferBarrier(curState: ResourceState, newState: ResourceState, buffer: vk.VkBuffer) vk.VkBufferMemoryBarrier2 {
    return vk.VkBufferMemoryBarrier2{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
        .srcStageMask = @intFromEnum(curState.stage),
        .srcAccessMask = @intFromEnum(curState.access),
        .dstStageMask = @intFromEnum(newState.stage),
        .dstAccessMask = @intFromEnum(newState.access),
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .buffer = buffer,
        .offset = 0,
        .size = vk.VK_WHOLE_SIZE, // whole Buffer
    };
}

fn createSubresourceRange(mask: u32, mipLevel: u32, levelCount: u32, arrayLayer: u32, layerCount: u32) vk.VkImageSubresourceRange {
    return vk.VkImageSubresourceRange{ .aspectMask = mask, .baseMipLevel = mipLevel, .levelCount = levelCount, .baseArrayLayer = arrayLayer, .layerCount = layerCount };
}

fn createAttachment(renderType: vh.ImgType, imgView: vk.VkImageView, clear: bool) vk.VkRenderingAttachmentInfo {
    const clearValue: vk.VkClearValue = switch (renderType) {
        .Color => .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.1, 1.0 } } },
        .Depth, .Stencil => .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
    };

    return vk.VkRenderingAttachmentInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = imgView,
        .imageLayout = vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        .loadOp = if (clear) vk.VK_ATTACHMENT_LOAD_OP_CLEAR else vk.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = clearValue, // ✓ Now correct per type
    };
}
