const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const Swapchain = @import("swapchain.zig").Swapchain;

// Import QueueFamilies from device.zig
const QueueFamilies = @import("device.zig").QueueFamilies;

pub fn createCmdPool(device: c.VkDevice, queueFamilyIndex: u32) !c.VkCommandPool {
    const poolInfo = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queueFamilyIndex,
    };

    var pool: c.VkCommandPool = undefined;

    if (c.vkCreateCommandPool(device, &poolInfo, null, &pool) != c.VK_SUCCESS) {
        std.log.err("Could not create CMD Pool\n", .{});
        return error.CmdPool;
    }

    return pool;
}

pub fn createCmdBuffer(device: c.VkDevice, cmdPool: c.VkCommandPool) !c.VkCommandBuffer {
    const allocInfo = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = cmdPool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var buffer: c.VkCommandBuffer = undefined;

    if (c.vkAllocateCommandBuffers(device, &allocInfo, &buffer) != c.VK_SUCCESS) {
        std.log.err("Could not create CMD Buffer\n", .{});
        return error.CmdBuffer;
    }

    return buffer;
}

// Fix 2: Updated recordCommandBuffer function in command.zig
pub fn recordCommandBuffer(cmdBuffer: c.VkCommandBuffer, extent: c.VkExtent2D, imageViews: []c.VkImageView, pipeline: c.VkPipeline, imageIndex: u32, swapchain: Swapchain) !void {
    const beginInfo = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = 0,
        .pInheritanceInfo = null,
    };
    if (c.vkBeginCommandBuffer(cmdBuffer, &beginInfo) != c.VK_SUCCESS) {
        std.log.err("Could not record CMD Buffer\n", .{});
        return error.RecordCmdBuffer;
    }

    // Add image layout transition for swapchain image
    const barrier = c.VkImageMemoryBarrier{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = swapchain.images[imageIndex], // Need to pass swapchain images too
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .srcAccessMask = 0,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    c.vkCmdPipelineBarrier(cmdBuffer, c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0, null, 0, null, 1, &barrier);

    const clear_color = c.VkClearValue{
        .color = .{ .float32 = .{ 0.0, 0.0, 0.1, 1.0 } },
    };

    const viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor_rect = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    c.vkCmdSetViewport(cmdBuffer, 0, 1, &viewport);
    c.vkCmdSetScissor(cmdBuffer, 0, 1, &scissor_rect);

    const color_attachment_info = c.VkRenderingAttachmentInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = imageViews[imageIndex], // Use correct image index
        .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .resolveMode = c.VK_RESOLVE_MODE_NONE,
        .resolveImageView = null,
        .resolveImageLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = clear_color,
    };

    const rendering_info = c.VkRenderingInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{ .extent = extent, .offset = .{ .x = 0, .y = 0 } },
        .layerCount = 1,
        .viewMask = 0,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_info,
        .pDepthAttachment = null,
        .pStencilAttachment = null,
    };

    c.vkCmdBeginRendering(cmdBuffer, &rendering_info);
    c.vkCmdBindPipeline(cmdBuffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
    c.vkCmdDraw(cmdBuffer, 3, 1, 0, 0);
    c.vkCmdEndRendering(cmdBuffer);

    // Transition back to present layout
    const present_barrier = c.VkImageMemoryBarrier{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .oldLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .newLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = swapchain.images[imageIndex],
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .srcAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dstAccessMask = 0,
    };

    c.vkCmdPipelineBarrier(cmdBuffer, c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, null, 0, null, 1, &present_barrier);

    _ = c.vkEndCommandBuffer(cmdBuffer);
}
