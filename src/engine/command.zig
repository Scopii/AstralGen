const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const Swapchain = @import("swapchain.zig").Swapchain;
const Pipeline = @import("pipeline.zig").Pipeline;
const check = @import("error.zig").check;

// Import QueueFamilies from device.zig
const QueueFamilies = @import("device.zig").QueueFamilies;

pub const CmdManager = struct {};

pub fn createCmdPool(gpi: c.VkDevice, familyIndex: u32) !c.VkCommandPool {
    const poolInfo = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = familyIndex,
    };
    var pool: c.VkCommandPool = undefined;
    try check(c.vkCreateCommandPool(gpi, &poolInfo, null, &pool), "Could not Create Cmd Pool");

    return pool;
}

pub fn createCmdBuffer(gpi: c.VkDevice, cmdPool: c.VkCommandPool) !c.VkCommandBuffer {
    const allocInfo = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = cmdPool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    var buffer: c.VkCommandBuffer = undefined;
    try check(c.vkAllocateCommandBuffers(gpi, &allocInfo, &buffer), "Could not create CMD Buffer");

    return buffer;
}

// Synchronization2 command buffer recording
pub fn recordCmdBufferSync2(swapchain: Swapchain, pipeline: Pipeline, cmdBuffer: c.VkCommandBuffer, imageIndex: u32) !void {
    // Use VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT for better driver optimization
    const beginInfo = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        //.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, // Hint to driver
        .pInheritanceInfo = null,
    };
    try check(c.vkBeginCommandBuffer(cmdBuffer, &beginInfo), "Could not record CMD Buffer");

    // Sync2: Transition swapchain image to color attachment
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
        .image = swapchain.imageBucket.images[imageIndex],
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    const depInfo = c.VkDependencyInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &imageBarrier,
    };
    c.vkCmdPipelineBarrier2(cmdBuffer, &depInfo);

    // Set viewport and scissor
    const viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swapchain.extent.width),
        .height = @floatFromInt(swapchain.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    c.vkCmdSetViewport(cmdBuffer, 0, 1, &viewport);

    const scissor_rect = c.VkRect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = swapchain.extent };
    c.vkCmdSetScissor(cmdBuffer, 0, 1, &scissor_rect);

    // Begin rendering
    const color_attachment_info = c.VkRenderingAttachmentInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = swapchain.imageBucket.imageViews[imageIndex],
        .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .resolveMode = c.VK_RESOLVE_MODE_NONE,
        .resolveImageView = null,
        .resolveImageLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR, //
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.1, 1.0 } } },
    };

    const rendering_info = c.VkRenderingInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{ .extent = swapchain.extent, .offset = .{ .x = 0, .y = 0 } },
        .layerCount = 1,
        .viewMask = 0,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_info,
        .pDepthAttachment = null,
        .pStencilAttachment = null,
    };

    c.vkCmdBeginRendering(cmdBuffer, &rendering_info);
    c.vkCmdBindPipeline(cmdBuffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.handle);
    c.vkCmdDraw(cmdBuffer, 3, 1, 0, 0);
    c.vkCmdEndRendering(cmdBuffer);

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
        .image = swapchain.imageBucket.images[imageIndex],
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    const presentDepInfo = c.VkDependencyInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &presentBarrier,
    };
    c.vkCmdPipelineBarrier2(cmdBuffer, &presentDepInfo);

    try check(c.vkEndCommandBuffer(cmdBuffer), "Could not end command buffer");
}
