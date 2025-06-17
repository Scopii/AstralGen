const std = @import("std");
const c = @import("../../c.zig");
const Swapchain = @import("Swapchain.zig").Swapchain;
const GraphicsPipeline = @import("PipelineManager.zig").GraphicsPipeline;
const ComputePipeline = @import("PipelineManager.zig").ComputePipeline;
const check = @import("../error.zig").check;

pub const CmdManager = struct {
    pool: c.VkCommandPool,

    pub fn init(gpi: c.VkDevice, graphics: u32) !CmdManager {
        return .{
            .pool = try createCmdPool(gpi, graphics),
        };
    }

    pub fn deinit(self: *CmdManager, gpi: c.VkDevice) void {
        c.vkDestroyCommandPool(gpi, self.pool, null);
    }

    pub fn createCmdBuffer(self: *const CmdManager, gpi: c.VkDevice) !c.VkCommandBuffer {
        const allocInf = c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = self.pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };
        var buff: c.VkCommandBuffer = undefined;
        try check(c.vkAllocateCommandBuffers(gpi, &allocInf, &buff), "Could not create CMD Buffer");
        return buff;
    }
};

fn createCmdPool(gpi: c.VkDevice, familyIndex: u32) !c.VkCommandPool {
    const poolInf = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT | //Allow individual rerecording of cmds, without this they have to be reset together
            c.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT, // Hint that cmd buffers are rerecorded often
        .queueFamilyIndex = familyIndex,
    };
    var pool: c.VkCommandPool = undefined;
    try check(c.vkCreateCommandPool(gpi, &poolInf, null, &pool), "Could not create Cmd Pool");
    return pool;
}

pub fn recordComputeCmdBuffer(
    swapchain: *Swapchain,
    cmd: c.VkCommandBuffer,
    imageIndex: u32,
    computePipe: *const ComputePipeline,
    descriptorSet: c.VkDescriptorSet,
) !void {
    const beginInf = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, // Hint to driver
        //.flags = c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT, // Allow re-use
    };
    try check(c.vkBeginCommandBuffer(cmd, &beginInf), "could not Begin CmdBuffer");

    // transition our main draw image into general layout so we can write into it
    // we will overwrite it all so we dont care about what was the older layout
    const imageBarrier = c.VkImageMemoryBarrier2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
        .srcAccessMask = 0, // c.VK_ACCESS_2_MEMORY_WRITE_BIT,
        .dstStageMask = c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .dstAccessMask = c.VK_ACCESS_2_MEMORY_WRITE_BIT | c.VK_ACCESS_2_MEMORY_READ_BIT,
        .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = c.VK_IMAGE_LAYOUT_GENERAL,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = swapchain.renderImage.image,
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    const depInf = c.VkDependencyInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &imageBarrier,
    };
    c.vkCmdPipelineBarrier2(cmd, &depInf);

    //try self.computeDraw(cmd);
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, computePipe.handle);
    c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, computePipe.layout, 0, 1, &descriptorSet, 0, null);
    const groupCountX = (swapchain.renderImage.extent3d.width + 7) / 8;
    const groupCountY = (swapchain.renderImage.extent3d.height + 7) / 8;
    c.vkCmdDispatch(cmd, groupCountX, groupCountY, 1);

    // Barrier 2 & 3: Transition renderImage to Transfer Src and swapchain image to Transfer Dst
    const imageBarrier2 = c.VkImageMemoryBarrier2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .srcAccessMask = c.VK_ACCESS_2_SHADER_WRITE_BIT,
        .dstStageMask = c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
        .dstAccessMask = c.VK_ACCESS_2_TRANSFER_READ_BIT,
        .oldLayout = c.VK_IMAGE_LAYOUT_GENERAL,
        .newLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = swapchain.renderImage.image,
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    const depInf2 = c.VkDependencyInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &imageBarrier2,
    };
    c.vkCmdPipelineBarrier2(cmd, &depInf2);

    const imageBarrier3 = c.VkImageMemoryBarrier2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
        .srcAccessMask = 0,
        .dstStageMask = c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
        .dstAccessMask = c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
        .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = swapchain.swapBuckets[imageIndex].image,
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    const depInfo3 = c.VkDependencyInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &imageBarrier3,
    };
    c.vkCmdPipelineBarrier2(cmd, &depInfo3);

    copyImageToImage(cmd, swapchain.renderImage.image, swapchain.swapBuckets[imageIndex].image, swapchain.extent, swapchain.extent);

    const imageBarrier4 = c.VkImageMemoryBarrier2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
        .srcAccessMask = c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
        .dstStageMask = c.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
        .dstAccessMask = 0,
        .oldLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .newLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = swapchain.swapBuckets[imageIndex].image,
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    const depInfo4 = c.VkDependencyInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &imageBarrier4,
    };
    c.vkCmdPipelineBarrier2(cmd, &depInfo4);
    try check(c.vkEndCommandBuffer(cmd), "Could not End Cmd Buffer");
}

pub fn recCmdBuffer(swapchain: *Swapchain, pipeline: *GraphicsPipeline, cmdBuff: c.VkCommandBuffer, imageIndex: u32) !void {
    const beginInf = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, // Hint to driver
        //.flags = c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT, // Allow re-use
        .pInheritanceInfo = null,
    };
    try check(c.vkBeginCommandBuffer(cmdBuff, &beginInf), "Could not record CMD Buffer");

    // Sync2
    const imageBarrier = c.VkImageMemoryBarrier2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
        .srcAccessMask = 0,
        .dstStageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
        .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = swapchain.swapBuckets[imageIndex].image,
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    const depInf = c.VkDependencyInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &imageBarrier,
    };
    c.vkCmdPipelineBarrier2(cmdBuff, &depInf);

    // Set viewport and scissor
    const viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swapchain.extent.width),
        .height = @floatFromInt(swapchain.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    c.vkCmdSetViewport(cmdBuff, 0, 1, &viewport);

    const scissor_rect = c.VkRect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = swapchain.extent };
    c.vkCmdSetScissor(cmdBuff, 0, 1, &scissor_rect);

    // Begin rendering
    const colorAttachInf = c.VkRenderingAttachmentInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = swapchain.swapBuckets[imageIndex].view,
        .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .resolveMode = c.VK_RESOLVE_MODE_NONE,
        .resolveImageView = null,
        .resolveImageLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE, //
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.1, 1.0 } } },
    };

    const renderInf = c.VkRenderingInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{ .extent = swapchain.extent, .offset = .{ .x = 0, .y = 0 } },
        .layerCount = 1,
        .viewMask = 0,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorAttachInf,
        .pDepthAttachment = null,
        .pStencilAttachment = null,
    };

    c.vkCmdBeginRendering(cmdBuff, &renderInf);
    c.vkCmdBindPipeline(cmdBuff, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.handle);
    c.vkCmdDraw(cmdBuff, 3, 1, 0, 0);
    c.vkCmdEndRendering(cmdBuff);

    // Sync2: Transition back to present layout
    const presentBarrier = c.VkImageMemoryBarrier2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
        .dstStageMask = c.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
        .dstAccessMask = 0,
        .oldLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .newLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = swapchain.swapBuckets[imageIndex].image,
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    const presentDepInf = c.VkDependencyInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &presentBarrier,
    };
    c.vkCmdPipelineBarrier2(cmdBuff, &presentDepInf);

    try check(c.vkEndCommandBuffer(cmdBuff), "Could not end command buffer");
}

// Compute Test NOT IN USE
pub fn computeDraw(self: *Swapchain, cmd: c.VkCommandBuffer) !void {
    const clearColor = c.VkClearColorValue{ .float32 = .{ 0.0, 0.0, 0.1, 1.0 } };
    const clearRange = c.VkImageSubresourceRange{
        .baseMipLevel = 0,
        .levelCount = 1,
        .baseArrayLayer = 0,
        .layerCount = 1,
        .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
    };

    c.vkCmdClearColorImage(cmd, self.renderImage.image, c.VK_IMAGE_LAYOUT_GENERAL, &clearColor, 1, &clearRange);
}

pub fn copyImageToImage(cmd: c.VkCommandBuffer, src: c.VkImage, dst: c.VkImage, srcSize: c.VkExtent2D, dstSize: c.VkExtent2D) void {
    var blitRegion = c.VkImageBlit2{ .sType = c.VK_STRUCTURE_TYPE_IMAGE_BLIT_2 };
    blitRegion.srcOffsets[1].x = @intCast(srcSize.width);
    blitRegion.srcOffsets[1].y = @intCast(srcSize.height);
    blitRegion.srcOffsets[1].z = 1;

    blitRegion.dstOffsets[1].x = @intCast(dstSize.width);
    blitRegion.dstOffsets[1].y = @intCast(dstSize.height);
    blitRegion.dstOffsets[1].z = 1;

    blitRegion.srcSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    blitRegion.srcSubresource.baseArrayLayer = 0;
    blitRegion.srcSubresource.layerCount = 1;
    blitRegion.srcSubresource.mipLevel = 0;

    blitRegion.dstSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    blitRegion.dstSubresource.baseArrayLayer = 0;
    blitRegion.dstSubresource.layerCount = 1;
    blitRegion.dstSubresource.mipLevel = 0;

    var blitInfo = c.VkBlitImageInfo2{ .sType = c.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2 };
    blitInfo.dstImage = dst;
    blitInfo.dstImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    blitInfo.srcImage = src;
    blitInfo.srcImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    blitInfo.filter = c.VK_FILTER_LINEAR;
    blitInfo.regionCount = 1;
    blitInfo.pRegions = &blitRegion;

    c.vkCmdBlitImage2(cmd, &blitInfo); // Can copy even with different Image Sizes/Formats
    //c.vkCmdCopyImage2(cmd, &blitInfo); //Faster but more restricted, TODO: Testing later!
    // writing new functions might be worth here
}
