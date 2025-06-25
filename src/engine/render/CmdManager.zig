const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const Swapchain = @import("Swapchain.zig").Swapchain;
const PipelineBucket = @import("PipelineBucket.zig").PipelineBucket;
const PipelineType = @import("PipelineBucket.zig").PipelineType;
const Context = @import("Context.zig").Context;
const check = @import("../error.zig").check;

pub const CmdManager = struct {
    alloc: Allocator,
    gpi: c.VkDevice,
    pool: c.VkCommandPool,
    cmds: []c.VkCommandBuffer,

    pub fn init(alloc: Allocator, context: *const Context, maxInFlight: u32) !CmdManager {
        const gpi = context.gpi;
        const family = context.families.graphics;

        const pool = try createCmdPool(gpi, family);
        const cmds = try alloc.alloc(c.VkCommandBuffer, maxInFlight);
        for (0..maxInFlight) |i| {
            cmds[i] = try createCmd(gpi, pool);
        }

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .pool = pool,
            .cmds = cmds,
        };
    }

    pub fn deinit(self: *CmdManager, gpi: c.VkDevice) void {
        self.alloc.free(self.cmds);
        c.vkDestroyCommandPool(gpi, self.pool, null);
    }

    pub fn getCmd(self: *const CmdManager, cpuFrame: u32) c.VkCommandBuffer {
        return self.cmds[cpuFrame];
    }

    pub fn recComputeCmd(
        _: *CmdManager,
        cmd: c.VkCommandBuffer,
        swapchain: *Swapchain,
        computePipe: *const PipelineBucket,
        descriptorSet: c.VkDescriptorSet,
    ) !void {
        const index = swapchain.index;
        try beginCmd(cmd, c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT); //c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT

        // Transition Image into general layout so we can write into it, Overwrites all so we dont care about the older layout
        const imageBarrier = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
            0,
            c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            c.VK_ACCESS_2_MEMORY_WRITE_BIT | c.VK_ACCESS_2_MEMORY_READ_BIT,
            c.VK_IMAGE_LAYOUT_UNDEFINED,
            c.VK_IMAGE_LAYOUT_GENERAL,
            swapchain.renderImage.image,
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(cmd, &.{imageBarrier});
        c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, computePipe.handle);
        c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, computePipe.layout, 0, 1, &descriptorSet, 0, null);
        const groupCountX = (swapchain.renderImage.extent3d.width + 7) / 8;
        const groupCountY = (swapchain.renderImage.extent3d.height + 7) / 8;
        c.vkCmdDispatch(cmd, groupCountX, groupCountY, 1);

        // Barrier 2 & 3: Transition renderImage to Transfer Src and swapchain image to Transfer Dst
        const imageBarrier2 = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            c.VK_ACCESS_2_SHADER_WRITE_BIT,
            c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
            c.VK_ACCESS_2_TRANSFER_READ_BIT,
            c.VK_IMAGE_LAYOUT_GENERAL,
            c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            swapchain.renderImage.image,
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );

        const imageBarrier3 = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
            0,
            c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
            c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
            c.VK_IMAGE_LAYOUT_UNDEFINED,
            c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            swapchain.swapBuckets[index].image,
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(cmd, &.{ imageBarrier2, imageBarrier3 });

        copyImageToImage(cmd, swapchain.renderImage.image, swapchain.swapBuckets[index].image, swapchain.extent, swapchain.extent);

        const imageBarrier4 = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
            c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
            c.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
            0,
            c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            swapchain.swapBuckets[index].image,
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(cmd, &.{imageBarrier4});

        try check(c.vkEndCommandBuffer(cmd), "Could not End Cmd Buffer");
    }

    pub fn recRenderingCmd(_: *CmdManager, cmd: c.VkCommandBuffer, swapchain: *Swapchain, pipeline: *PipelineBucket, pipeType: PipelineType) !void {
        const index = swapchain.index;
        try beginCmd(cmd, c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT); // c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT allow re-use

        const imageBarrier = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
            0,
            c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            c.VK_IMAGE_LAYOUT_UNDEFINED,
            c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            swapchain.swapBuckets[index].image,
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(cmd, &.{imageBarrier});

        // Set viewport and scissor
        const viewport = c.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(swapchain.extent.width),
            .height = @floatFromInt(swapchain.extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        c.vkCmdSetViewport(cmd, 0, 1, &viewport);

        const scissor_rect = c.VkRect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = swapchain.extent };
        c.vkCmdSetScissor(cmd, 0, 1, &scissor_rect);

        // Begin rendering
        const colorAttachInf = c.VkRenderingAttachmentInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = swapchain.swapBuckets[index].view,
            .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .resolveMode = c.VK_RESOLVE_MODE_NONE,
            .resolveImageView = null,
            .resolveImageLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
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

        c.vkCmdBeginRendering(cmd, &renderInf);
        c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.handle);

        if (pipeType == .mesh) {
            c.pfn_vkCmdDrawMeshTasksEXT.?(cmd, 1, 1, 1); //replaces vkCmdDraw.
        } else {
            c.vkCmdDraw(cmd, 3, 1, 0, 0);
        }

        c.vkCmdEndRendering(cmd);

        // Transition back to present layout
        const presentBarrier = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            c.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
            0,
            c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            swapchain.swapBuckets[index].image,
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(cmd, &.{presentBarrier});

        try check(c.vkEndCommandBuffer(cmd), "Could not End Cmd Recording");
    }
};

pub fn beginCmd(cmd: c.VkCommandBuffer, flags: c.VkCommandBufferUsageFlags) !void {
    const beginInf = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = flags,
        .pInheritanceInfo = null,
    };
    try check(c.vkBeginCommandBuffer(cmd, &beginInf), "could not Begin CmdBuffer");
}

fn createCmd(gpi: c.VkDevice, pool: c.VkCommandPool) !c.VkCommandBuffer {
    const allocInf = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    var buff: c.VkCommandBuffer = undefined;
    try check(c.vkAllocateCommandBuffers(gpi, &allocInf, &buff), "Could not create CMD Buffer");
    return buff;
}

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
    return c.VkImageSubresourceLayers{
        .aspectMask = mask,
        .mipLevel = mipLevel,
        .baseArrayLayer = arrayLayer,
        .layerCount = layerCount,
    };
}

fn createImageMemoryBarrier2(
    srcStageMask: u64,
    srcAccessMask: u64,
    dstStageMask: u64,
    dstAccessMask: u64,
    oldLayout: u32,
    newLayout: u32,
    image: c.VkImage,
    subResRange: c.VkImageSubresourceRange,
) c.VkImageMemoryBarrier2 {
    return c.VkImageMemoryBarrier2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = srcStageMask,
        .srcAccessMask = srcAccessMask,
        .dstStageMask = dstStageMask,
        .dstAccessMask = dstAccessMask,
        .oldLayout = oldLayout,
        .newLayout = newLayout,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = subResRange,
    };
}

pub fn copyImageToImage(cmd: c.VkCommandBuffer, src: c.VkImage, dst: c.VkImage, srcSize: c.VkExtent2D, dstSize: c.VkExtent2D) void {
    const blitRegion = c.VkImageBlit2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_BLIT_2,
        .srcSubresource = createSubresourceLayers(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
        .srcOffsets = .{
            .{ .x = 0, .y = 0, .z = 0 }, // Offset top-left-front corner
            .{ .x = @intCast(srcSize.width), .y = @intCast(srcSize.height), .z = 1 }, // Offset bottom-right-back corner
        },
        .dstSubresource = createSubresourceLayers(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
        .dstOffsets = .{
            .{ .x = 0, .y = 0, .z = 0 }, // Offset top-left-front corner
            .{ .x = @intCast(dstSize.width), .y = @intCast(dstSize.height), .z = 1 }, // Offset bottom-right-back corner
        },
    };

    const blitInfo = c.VkBlitImageInfo2{
        .sType = c.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2,
        .dstImage = dst,
        .dstImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .srcImage = src,
        .srcImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .filter = c.VK_FILTER_LINEAR,
        .regionCount = 1,
        .pRegions = &blitRegion,
    };

    c.vkCmdBlitImage2(cmd, &blitInfo);
}
