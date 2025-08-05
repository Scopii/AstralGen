const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const RenderImage = @import("ResourceManager.zig").RenderImage;
const PipelineBucket = @import("PipelineBucket.zig").Pipeline;
const PipelineType = @import("PipelineBucket.zig").PipelineType;
const Context = @import("Context.zig").Context;
const Swapchain = @import("SwapchainManager.zig").Swapchain;
const check = @import("error.zig").check;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const MAX_WINDOWS = @import("../config.zig").MAX_WINDOWS;

pub const CmdManager = struct {
    alloc: Allocator,
    gpi: c.VkDevice,
    pool: c.VkCommandPool,
    activeFrame: ?u8 = null,
    lastUpdate: u8 = 0,
    primaryCmds: []c.VkCommandBuffer,
    computeCmds: []c.VkCommandBuffer,
    graphicsCmds: []c.VkCommandBuffer,
    meshCmds: []c.VkCommandBuffer,
    blitBarriers: [MAX_WINDOWS + 1]c.VkImageMemoryBarrier2 = undefined,
    needNewRecording: bool = true,

    pub fn init(alloc: Allocator, context: *const @import("Context.zig").Context, maxInFlight: u32) !CmdManager {
        const gpi = context.gpi;
        const family = context.families.graphics;
        const pool = try createCmdPool(gpi, family);

        const primaryCmds = try alloc.alloc(c.VkCommandBuffer, maxInFlight);
        const computeCmds = try alloc.alloc(c.VkCommandBuffer, maxInFlight);
        const graphicsCmds = try alloc.alloc(c.VkCommandBuffer, maxInFlight);
        const meshCmds = try alloc.alloc(c.VkCommandBuffer, maxInFlight);

        for (0..maxInFlight) |i| {
            primaryCmds[i] = try createCmd(gpi, pool, c.VK_COMMAND_BUFFER_LEVEL_PRIMARY);
            computeCmds[i] = try createCmd(gpi, pool, c.VK_COMMAND_BUFFER_LEVEL_SECONDARY);
            graphicsCmds[i] = try createCmd(gpi, pool, c.VK_COMMAND_BUFFER_LEVEL_SECONDARY);
            meshCmds[i] = try createCmd(gpi, pool, c.VK_COMMAND_BUFFER_LEVEL_SECONDARY);
        }

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .pool = pool,
            .primaryCmds = primaryCmds,
            .computeCmds = computeCmds,
            .graphicsCmds = graphicsCmds,
            .meshCmds = meshCmds,
        };
    }

    pub fn deinit(self: *CmdManager) void {
        self.alloc.free(self.primaryCmds);
        self.alloc.free(self.computeCmds);
        self.alloc.free(self.graphicsCmds);
        self.alloc.free(self.meshCmds);
        c.vkDestroyCommandPool(self.gpi, self.pool, null);
    }

    pub fn beginRecording(self: *CmdManager, frameInFlight: u8) !void {
        if (self.activeFrame != null) return error.RecordingInProgress;
        const cmd = self.primaryCmds[frameInFlight];
        const beginInf = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = 0, //c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT / VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
            .pInheritanceInfo = null,
        };
        try check(c.vkBeginCommandBuffer(cmd, &beginInf), "could not Begin CmdBuffer");
        self.activeFrame = frameInFlight;
        if (self.needNewRecording == true) self.lastUpdate = frameInFlight;
    }

    pub fn endRecording(self: *CmdManager) !c.VkCommandBuffer {
        const activeFrame = self.activeFrame orelse return error.NoActiveRecording;
        const cmd = self.primaryCmds[activeFrame];
        try check(c.vkEndCommandBuffer(cmd), "Could not End Cmd Buffer");
        self.activeFrame = null;
        self.needNewRecording = false;
        return cmd;
    }

    pub fn getCmd(self: *const CmdManager, frameInFlight: u8) c.VkCommandBuffer {
        return self.primaryCmds[frameInFlight];
    }

    pub fn recordComputePass(self: *CmdManager, renderImage: *RenderImage, pipe: *const PipelineBucket, set: c.VkDescriptorSet) !void {
        const activeFrame = self.activeFrame orelse return error.ActiveCmdBlocked;
        const primaryCmd = self.primaryCmds[activeFrame];
        const computeCmd = self.computeCmds[activeFrame];

        const inheritanceInfo = c.VkCommandBufferInheritanceInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO,
            .pNext = null,
            .subpass = 0,
            .occlusionQueryEnable = c.VK_FALSE,
            .queryFlags = 0,
            .pipelineStatistics = 0,
        };

        // 1. Begin recording the secondary command buffer
        const beginInfo = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = &inheritanceInfo, // No complex inheritance needed for compute
        };
        try check(c.vkBeginCommandBuffer(computeCmd, &beginInfo), "Could not begin compute command buffer");

        // 2. Record commands into the secondary command buffer
        c.vkCmdBindPipeline(computeCmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, pipe.handle);
        c.vkCmdBindDescriptorSets(computeCmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, pipe.layout, 0, 1, &set, 0, null);
        c.vkCmdDispatch(computeCmd, (renderImage.extent3d.width + 7) / 8, (renderImage.extent3d.height + 7) / 8, 1);

        // 3. End recording of the secondary command buffer
        try check(c.vkEndCommandBuffer(computeCmd), "Could not end compute command buffer");

        // 4. Record pipeline barrier in primary command buffer
        const barrier = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
            0,
            c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            c.VK_ACCESS_2_SHADER_WRITE_BIT,
            renderImage.curLayout,
            c.VK_IMAGE_LAYOUT_GENERAL,
            renderImage.image,
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(primaryCmd, &.{barrier});
        renderImage.curLayout = c.VK_IMAGE_LAYOUT_GENERAL;

        // 5. Execute the secondary command buffer in the primary one
        c.vkCmdExecuteCommands(primaryCmd, 1, &computeCmd);
    }

    pub fn recordGraphicsPass(self: *CmdManager, renderImage: *RenderImage, pipe: *const PipelineBucket, pipeType: PipelineType) !void {
        const activeFrame = self.activeFrame orelse return error.ActiveCmdBlocked;
        const primaryCmd = self.primaryCmds[activeFrame];
        // Select the correct secondary command buffer based on pipeline type
        const gfxCmd = if (pipeType == .mesh) self.meshCmds[activeFrame] else self.graphicsCmds[activeFrame];

        // 1. Set up inheritance info for dynamic rendering
        const color_format = renderImage.format; // Assuming format is stored in RenderImage
        const renderingInheritanceInfo = c.VkCommandBufferInheritanceRenderingInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_RENDERING_INFO,
            .pNext = null,
            .colorAttachmentCount = 1,
            .pColorAttachmentFormats = &color_format,
            .depthAttachmentFormat = c.VK_FORMAT_UNDEFINED,
            .stencilAttachmentFormat = c.VK_FORMAT_UNDEFINED,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        };

        const inheritanceInfo = c.VkCommandBufferInheritanceInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO,
            .pNext = &renderingInheritanceInfo,
            .subpass = 0,
            .occlusionQueryEnable = c.VK_FALSE,
            .queryFlags = 0,
            .pipelineStatistics = 0,
        };

        const beginInfo = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT | c.VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT,
            .pInheritanceInfo = &inheritanceInfo,
        };

        // 2. Begin recording the secondary command buffer
        try check(c.vkBeginCommandBuffer(gfxCmd, &beginInfo), "Could not begin graphics command buffer");

        // 3. Record commands into the secondary command buffer
        const viewport = c.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(renderImage.extent3d.width),
            .height = @floatFromInt(renderImage.extent3d.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        c.vkCmdSetViewport(gfxCmd, 0, 1, &viewport);

        const scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = renderImage.extent3d.width, .height = renderImage.extent3d.height },
        };
        c.vkCmdSetScissor(gfxCmd, 0, 1, &scissor);

        c.vkCmdBindPipeline(gfxCmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipe.handle);
        if (pipeType == .mesh) c.pfn_vkCmdDrawMeshTasksEXT.?(gfxCmd, 1, 1, 1) else c.vkCmdDraw(gfxCmd, 3, 1, 0, 0);

        // 4. End recording of the secondary command buffer
        try check(c.vkEndCommandBuffer(gfxCmd), "Could not end graphics command buffer");

        // 5. Record barriers and begin rendering in the primary command buffer
        const barrier = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
            0,
            c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            renderImage.curLayout,
            c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            renderImage.image,
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(primaryCmd, &.{barrier});
        renderImage.curLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

        const colorAttachmentInfo = c.VkRenderingAttachmentInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = renderImage.view,
            .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .clearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.1, 1.0 } } },
        };

        const renderingInfo = c.VkRenderingInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
            // VUID-vkCmdExecuteCommands-flags-06024: flags must include SECONDARY_COMMAND_BUFFERS_BIT
            .flags = c.VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT,
            .renderArea = scissor,
            .layerCount = 1,
            .colorAttachmentCount = 1,
            .pColorAttachments = &colorAttachmentInfo,
            .pDepthAttachment = null,
            .pStencilAttachment = null,
        };
        c.vkCmdBeginRendering(primaryCmd, &renderingInfo);

        // 6. Execute the secondary command buffer
        c.vkCmdExecuteCommands(primaryCmd, 1, &gfxCmd);

        // 7. End rendering in the primary command buffer
        c.vkCmdEndRendering(primaryCmd);
    }

    pub fn blitToTargets(self: *CmdManager, renderImage: *RenderImage, targets: []const u8, swapchainMap: *CreateMapArray(Swapchain, MAX_WINDOWS, u8, MAX_WINDOWS, 0)) !void {
        const activeFrame = self.activeFrame orelse return error.ActiveCmdBlocked;
        const cmd = self.primaryCmds[activeFrame];

        var barriers = &self.blitBarriers;
        barriers[0] = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
            c.VK_ACCESS_2_MEMORY_WRITE_BIT,
            c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
            c.VK_ACCESS_2_TRANSFER_READ_BIT,
            renderImage.curLayout,
            c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            renderImage.image,
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        renderImage.curLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        for (targets, 1..) |id, i| {
            const swapchain = swapchainMap.getPtr(id);
            barriers[i] = createImageMemoryBarrier2(
                c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
                0,
                c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
                c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
                c.VK_IMAGE_LAYOUT_UNDEFINED,
                c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                swapchain.images[swapchain.curIndex],
                createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
            );
        }
        const barriersPtr1 = self.blitBarriers[0 .. targets.len + 1];
        createPipelineBarriers2(cmd, barriersPtr1);
        for (targets) |id| {
            const swapchain = swapchainMap.getPtr(id);
            copyImageToImage(
                cmd,
                renderImage.image,
                swapchain.images[swapchain.curIndex],
                .{ .width = renderImage.extent3d.width, .height = renderImage.extent3d.height },
                swapchain.extent,
            );
        }
        for (targets, 0..targets.len) |id, i| {
            const swapchain = swapchainMap.getPtr(id);
            barriers[i] = createImageMemoryBarrier2(
                c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
                c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
                c.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
                0,
                c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                swapchain.images[swapchain.curIndex],
                createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
            );
        }
        const barriersPtr2 = self.blitBarriers[0..targets.len];
        createPipelineBarriers2(cmd, barriersPtr2);
    }
};

fn createCmd(gpi: c.VkDevice, pool: c.VkCommandPool, level: c.VkCommandBufferLevel) !c.VkCommandBuffer {
    const allocInf = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = level,
        .commandBufferCount = 1,
    };
    var cmd: c.VkCommandBuffer = undefined;
    try check(c.vkAllocateCommandBuffers(gpi, &allocInf, &cmd), "Could not create Cmd Buffer");
    return cmd;
}

fn createCmdPool(gpi: c.VkDevice, familyIndex: u32) !c.VkCommandPool {
    const poolInf = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT | c.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
        .queueFamilyIndex = familyIndex,
    };
    var pool: c.VkCommandPool = undefined;
    try check(c.vkCreateCommandPool(gpi, &poolInf, null, &pool), "Could not create Cmd Pool");
    return pool;
}

fn createPipelineBarriers2(cmd: c.VkCommandBuffer, barriers: []const c.VkImageMemoryBarrier2) void {
    const depInf = c.VkDependencyInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = @intCast(barriers.len),
        .pImageMemoryBarriers = barriers.ptr,
    };
    c.vkCmdPipelineBarrier2(cmd, &depInf);
}

fn createSubresourceRange(mask: u32, mipLevel: u32, levelCount: u32, arrayLayer: u32, layerCount: u32) c.VkImageSubresourceRange {
    return c.VkImageSubresourceRange{
        .aspectMask = mask,
        .baseMipLevel = mipLevel,
        .levelCount = levelCount,
        .baseArrayLayer = arrayLayer,
        .layerCount = layerCount,
    };
}

fn createSubresourceLayers(mask: u32, mipLevel: u32, arrayLayer: u32, layerCount: u32) c.VkImageSubresourceLayers {
    return c.VkImageSubresourceLayers{ .aspectMask = mask, .mipLevel = mipLevel, .baseArrayLayer = arrayLayer, .layerCount = layerCount };
}

fn createImageMemoryBarrier2(
    srcStage: u64,
    srcAccess: u64,
    dstStage: u64,
    dstAccess: u64,
    oldLayout: u32,
    newLayout: u32,
    image: c.VkImage,
    subResRange: c.VkImageSubresourceRange,
) c.VkImageMemoryBarrier2 {
    return c.VkImageMemoryBarrier2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = srcStage,
        .srcAccessMask = srcAccess,
        .dstStageMask = dstStage,
        .dstAccessMask = dstAccess,
        .oldLayout = oldLayout,
        .newLayout = newLayout,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = subResRange,
    };
}

pub fn copyImageToImage(cmd: c.VkCommandBuffer, srcImage: c.VkImage, dstImage: c.VkImage, srcSize: c.VkExtent2D, dstSize: c.VkExtent2D) void {
    const blitRegion = c.VkImageBlit2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_BLIT_2,
        .srcSubresource = createSubresourceLayers(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
        .srcOffsets = .{ .{ .x = 0, .y = 0, .z = 0 }, .{
            .x = @intCast(srcSize.width),
            .y = @intCast(srcSize.height),
            .z = 1,
        } },
        .dstSubresource = createSubresourceLayers(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
        .dstOffsets = .{ .{ .x = 0, .y = 0, .z = 0 }, .{
            .x = @intCast(dstSize.width),
            .y = @intCast(dstSize.height),
            .z = 1,
        } },
    };
    const blitInfo = c.VkBlitImageInfo2{
        .sType = c.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2,
        .dstImage = dstImage,
        .dstImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .srcImage = srcImage,
        .srcImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .filter = c.VK_FILTER_LINEAR,
        .regionCount = 1,
        .pRegions = &blitRegion,
    };
    c.vkCmdBlitImage2(cmd, &blitInfo);
}
