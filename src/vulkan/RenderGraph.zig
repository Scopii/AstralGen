const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const rc = @import("../configs/renderConfig.zig");
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const Resource = @import("resources/ResourceManager.zig").Resource;
const GpuImage = @import("resources/ResourceManager.zig").Resource.GpuImage;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const PushConstants = @import("resources/DescriptorManager.zig").PushConstants;
const vkFn = @import("../modules/vk.zig");
const sc = @import("../configs/shaderConfig.zig");
const SwapchainManager = @import("SwapchainManager.zig");
const Command = @import("Command.zig").Command;

pub const ImageLayout = enum(vk.VkImageLayout) {
    Undefined = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    General = vk.VK_IMAGE_LAYOUT_GENERAL, // for Storage Images / Compute Writes
    Attachment = vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL, // Replaces All Attachments (Outputs)
    ReadOnly = vk.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL, // Replaces All AttachmentReads (Inputs)
    TransferSrc = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    TransferDst = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    PresentSrc = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    //more exist
};

pub const PipeStage = enum(vk.VkPipelineStageFlagBits2) { //( SHOULD BE CORRECT ORDER)
    TopOfPipe = vk.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
    Compute = vk.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
    VertShader = vk.VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT,
    TaskShader = vk.VK_PIPELINE_STAGE_2_TASK_SHADER_BIT_EXT,
    MeshShader = vk.VK_PIPELINE_STAGE_2_MESH_SHADER_BIT_EXT,
    FragShader = vk.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
    EarlyFragTest = vk.VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
    ColorAtt = vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
    LatFragTest = vk.VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
    AllGraphics = vk.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
    Transfer = vk.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
    AllCmds = vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
    BotOfPipe = vk.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
    //.. more exist
};

pub const PipeAccess = enum(vk.VkAccessFlagBits2) {
    None = 0,
    ShaderRead = vk.VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
    ShaderWrite = vk.VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
    ShaderReadWrite = vk.VK_ACCESS_2_SHADER_STORAGE_READ_BIT | vk.VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,

    ColorAttWrite = vk.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
    ColorAttRead = vk.VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT,
    ColorAttReadWrite = vk.VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT | vk.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,

    DepthStencilRead = vk.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
    DepthStencilWrite = vk.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,

    TransferRead = vk.VK_ACCESS_2_TRANSFER_READ_BIT,
    TransferWrite = vk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
    TransferReadWrite = vk.VK_ACCESS_2_TRANSFER_READ_BIT | vk.VK_ACCESS_2_TRANSFER_WRITE_BIT,

    MemoryRead = vk.VK_ACCESS_2_MEMORY_READ_BIT,
    MemoryWrite = vk.VK_ACCESS_2_MEMORY_WRITE_BIT,
    MemoryReadWrite = vk.VK_ACCESS_2_MEMORY_READ_BIT | vk.VK_ACCESS_2_MEMORY_WRITE_BIT,
    //.. more exist
};

pub const ResourceState = struct {
    stage: PipeStage = .TopOfPipe,
    access: PipeAccess = .None,
    layout: ImageLayout = .Undefined,
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
            const destResource = try resMan.getResourcePtr(transfer.dstResId);
            // Transition Destination to TransferDst
            try self.createBarrierIfNeeded(destResource.state, .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst }, destResource);
            cmd.copyBuffer(resMan.stagingBuffer.buffer, &transfer, destResource.resourceType.gpuBuf.buffer);
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

        for (pass.resUsages) |resUsage| {
            const resource = try resMan.getResourcePtr(resUsage.id);
            const neededState = ResourceState{ .stage = resUsage.stage, .access = resUsage.access, .layout = resUsage.layout };
            try self.createBarrierIfNeeded(resource.state, neededState, resource);
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

    pub fn recordPass(self: *RenderGraph, cmd: *const Command, pass: rc.Pass, pcs: PushConstants, validShaders: []const ShaderObject, resMan: *ResourceManager) !void {
        cmd.setPushConstants(self.pipeLayout, vk.VK_SHADER_STAGE_ALL, 0, @sizeOf(PushConstants), &pcs);
        cmd.bindShaders(validShaders);

        switch (pass.kind) {
            .compute => |comp| try recordCompute(cmd, comp.workgroups, pass.renderImgId, resMan),
            .graphics => |graphics| try recordGraphics(cmd, graphics.colorAtts, graphics.depthAtt, graphics.stencilAtt, pass, resMan),
            .taskOrMesh => |taskOrMesh| try recordGraphics(cmd, taskOrMesh.colorAtts, taskOrMesh.depthAtt, taskOrMesh.stencilAtt, pass, resMan),
        }
    }

    fn recordGraphics(cmd: *const Command, colorAtts: []const rc.Pass.Attachment, depthAtt: ?rc.Pass.Attachment, stencilAtt: ?rc.Pass.Attachment, pass: rc.Pass, resMan: *ResourceManager) !void {
        if (colorAtts.len > 8) return error.TooManyAttachments;
        const mainImg = if (pass.renderImgId) |imgId| try resMan.getImagePtr(imgId) else return error.GraphicsPassNeedsRenderImgId;

        const depthInf: ?vk.VkRenderingAttachmentInfo = if (depthAtt) |depth| blk: {
            const imgId = pass.resUsages[depth.resUsageSlot].id;
            const img = try resMan.getImagePtr(imgId);
            break :blk createAttachment(img.imgInf.imgType, img.view, depth.clear);
        } else null;

        const stencilInf: ?vk.VkRenderingAttachmentInfo = if (stencilAtt) |stencil| blk: {
            const imgId = pass.resUsages[stencil.resUsageSlot].id;
            const img = try resMan.getImagePtr(imgId);
            break :blk createAttachment(img.imgInf.imgType, img.view, stencil.clear);
        } else null;

        var colorInfs: [8]vk.VkRenderingAttachmentInfo = undefined;
        for (0..colorAtts.len) |i| {
            const color = colorAtts[i];
            const imgId = pass.resUsages[color.resUsageSlot].id;
            const img = try resMan.getImagePtr(imgId);
            colorInfs[i] = createAttachment(img.imgInf.imgType, img.view, color.clear);
        }

        cmd.beginRendering(mainImg.imgInf.extent.width, mainImg.imgInf.extent.height, colorInfs[0..colorAtts.len], depthInf, stencilInf);

        switch (pass.kind) {
            .compute => return error.ComputeLandedInGraphicsPass,
            .taskOrMesh => |taskOrMesh| cmd.drawMeshTasks(taskOrMesh.workgroups.x, taskOrMesh.workgroups.y, taskOrMesh.workgroups.z),
            .graphics => |graphics| {
                cmd.setEmptyVertexInput();
                cmd.draw(graphics.vertexCount, graphics.instanceCount, 0, 0);
            },
        }
        cmd.endRendering();
    }

    pub fn recordSwapchainBlits(self: *RenderGraph, cmd: *const Command, targets: []const u32, swapchainMap: *SwapchainManager.SwapchainMap, resMan: *ResourceManager) !void {
        // Render Image and Swapchain Preperations
        for (targets) |swapchainIndex| {
            const swapchain = swapchainMap.getPtrAtIndex(swapchainIndex);
            const renderImg = try resMan.getResourcePtr(swapchain.passImgId);
            try self.createBarrierIfNeeded(renderImg.state, .{ .stage = .Transfer, .access = .TransferRead, .layout = .TransferSrc }, renderImg);
            const swapchainImg = swapchain.images[swapchain.curIndex];
            try self.tempImgBarriers.append(createImageBarrier(.{}, .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst }, swapchainImg, .Color));
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
            const state = ResourceState{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst };
            const neededState = ResourceState{ .stage = .BotOfPipe, .access = .None, .layout = .PresentSrc };
            try self.tempImgBarriers.append(createImageBarrier(state, neededState, swapchain.images[swapchain.curIndex], .Color));
        }
        self.bakeBarriers(cmd);
    }

    fn bakeBarriers(self: *RenderGraph, cmd: *const Command) void {
        cmd.bakeBarriers(self.tempImgBarriers.items, self.tempBufBarriers.items);
        self.tempImgBarriers.clearRetainingCapacity();
        self.tempBufBarriers.clearRetainingCapacity();
    }
};

fn createImageBarrier(curState: ResourceState, newState: ResourceState, img: vk.VkImage, imgType: rc.ImgType) vk.VkImageMemoryBarrier2 {
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

fn createAttachment(renderType: rc.ImgType, imgView: vk.VkImageView, clear: bool) vk.VkRenderingAttachmentInfo {
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
