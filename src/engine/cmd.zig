const std = @import("std");
const c = @import("../c.zig");
const Swapchain = @import("swapchain.zig").Swapchain;
const Pipeline = @import("pipeline.zig").Pipeline;
const check = @import("error.zig").check;

pub const CmdManager = struct {};

pub fn createCmdPool(gpi: c.VkDevice, familyIndex: u32) !c.VkCommandPool {
    const poolInf = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT |
            c.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT, // Add transient flag for frequent reuse
        .queueFamilyIndex = familyIndex,
    };
    var pool: c.VkCommandPool = undefined;
    try check(c.vkCreateCommandPool(gpi, &poolInf, null, &pool), "Could not create Cmd Pool");
    return pool;
}

pub fn createCmdBuffer(gpi: c.VkDevice, cmdPool: c.VkCommandPool) !c.VkCommandBuffer {
    const allocInf = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = cmdPool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    var buff: c.VkCommandBuffer = undefined;
    try check(c.vkAllocateCommandBuffers(gpi, &allocInf, &buff), "Could not create CMD Buffer");
    return buff;
}

pub fn recCmdBuffer(swapchain: *Swapchain, pipeline: *Pipeline, cmdBuff: c.VkCommandBuffer, imageIndex: u32) !void {
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
        .image = swapchain.imageBuckets[imageIndex].image,
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
        .imageView = swapchain.imageBuckets[imageIndex].view,
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
        .image = swapchain.imageBuckets[imageIndex].image,
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
