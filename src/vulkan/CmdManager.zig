const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const Image = @import("ResourceManager.zig").GpuImage;
const Swapchain = @import("SwapchainManager.zig").Swapchain;
const PipelineBucket = @import("PipelineBucket.zig").ShaderPipeline;
const PipelineType = @import("PipelineBucket.zig").PipelineType;
const ComputePushConstants = @import("PipelineBucket.zig").ComputePushConstants;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const deviceAddress = @import("ResourceManager.zig").GpuBuffer.deviceAddress;
const MAX_WINDOWS = @import("../config.zig").MAX_WINDOWS;
const check = @import("error.zig").check;

pub const CmdManager = struct {
    alloc: Allocator,
    gpi: c.VkDevice,
    pool: c.VkCommandPool,
    activeFrame: ?u8 = null,
    primaryCmds: []c.VkCommandBuffer,
    blitBarriers: [MAX_WINDOWS + 1]c.VkImageMemoryBarrier2 = undefined,

    pub fn init(alloc: Allocator, context: *const @import("Context.zig").Context, maxInFlight: u32) !CmdManager {
        const gpi = context.gpi;
        const family = context.families.graphics;
        const pool = try createCmdPool(gpi, family);

        const primaryCmds = try alloc.alloc(c.VkCommandBuffer, maxInFlight);
        for (0..maxInFlight) |i| {
            primaryCmds[i] = try createCmd(gpi, pool, c.VK_COMMAND_BUFFER_LEVEL_PRIMARY);
        }

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .pool = pool,
            .primaryCmds = primaryCmds,
        };
    }

    pub fn deinit(self: *CmdManager) void {
        self.alloc.free(self.primaryCmds);
        c.vkDestroyCommandPool(self.gpi, self.pool, null);
    }

    pub fn beginRecording(self: *CmdManager, frameInFlight: u8) !void {
        if (self.activeFrame != null) return error.RecordingInProgress;
        const cmd = self.primaryCmds[frameInFlight];

        try check(c.vkResetCommandBuffer(cmd, 0), "could not reset command buffer"); // Might be optional

        const beginInf = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, //c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT
            .pInheritanceInfo = null,
        };
        try check(c.vkBeginCommandBuffer(cmd, &beginInf), "could not Begin CmdBuffer");
        self.activeFrame = frameInFlight;
    }

    pub fn endRecording(self: *CmdManager) !c.VkCommandBuffer {
        const activeFrame = self.activeFrame orelse return error.NoActiveRecording;
        const cmd = self.primaryCmds[activeFrame];
        try check(c.vkEndCommandBuffer(cmd), "Could not End Cmd Buffer");
        self.activeFrame = null;
        return cmd;
    }

    pub fn getCmd(self: *const CmdManager, frameInFlight: u8) c.VkCommandBuffer {
        return self.primaryCmds[frameInFlight];
    }

    pub fn recordComputePass(self: *CmdManager, renderImage: *Image, pipe: *const PipelineBucket, gpuAddress: deviceAddress, pushConstants: ComputePushConstants) !void {
        const activeFrame = self.activeFrame orelse return error.ActiveCmdBlocked;
        const cmd = self.primaryCmds[activeFrame];

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
        createPipelineBarriers2(cmd, &.{barrier});
        renderImage.curLayout = c.VK_IMAGE_LAYOUT_GENERAL;

        // Bind shader object/pipeline directly to the primary command buffer.

        const stages = [_]c.VkShaderStageFlagBits{c.VK_SHADER_STAGE_COMPUTE_BIT};
        c.pfn_vkCmdBindShadersEXT.?(cmd, 1, &stages, &pipe.shaderObjects.items[0].handle);
        c.vkCmdPushConstants(cmd, pipe.layout, c.VK_SHADER_STAGE_COMPUTE_BIT, 0, @sizeOf(ComputePushConstants), &pushConstants);

        const bufferBindingInf = c.VkDescriptorBufferBindingInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
            .address = gpuAddress,
            .usage = c.VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT,
        };
        c.pfn_vkCmdBindDescriptorBuffersEXT.?(cmd, 1, &bufferBindingInf);

        const bufferIndex: u32 = 0;
        const descriptorOffset: c.VkDeviceSize = 0;
        c.pfn_vkCmdSetDescriptorBufferOffsetsEXT.?(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, pipe.layout, 0, 1, &bufferIndex, &descriptorOffset);

        c.vkCmdDispatch(cmd, (renderImage.extent3d.width + 7) / 8, (renderImage.extent3d.height + 7) / 8, 1);
    }

    pub fn recordGraphicsPassShaderObject(self: *CmdManager, renderImage: *Image, pipe: *const PipelineBucket, pipeType: PipelineType) !void {
        const activeFrame = self.activeFrame orelse return error.ActiveCmdBlocked;
        const cmd = self.primaryCmds[activeFrame];

        // Image layout transition (same as before)
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
        createPipelineBarriers2(cmd, &.{barrier});
        renderImage.curLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

        const scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = renderImage.extent3d.width, .height = renderImage.extent3d.height },
        };

        const colorAttachInf = c.VkRenderingAttachmentInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = renderImage.view,
            .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .clearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.1, 1.0 } } },
        };

        const renderInf = c.VkRenderingInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
            .flags = 0,
            .renderArea = scissor,
            .layerCount = 1,
            .colorAttachmentCount = 1,
            .pColorAttachments = &colorAttachInf,
            .pDepthAttachment = null,
            .pStencilAttachment = null,
        };

        c.vkCmdBeginRendering(cmd, &renderInf);

        // Set dynamic viewport and scissor - use WithCount versions for shader objects
        const viewport = c.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(renderImage.extent3d.width),
            .height = @floatFromInt(renderImage.extent3d.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };

        // Use WithCount versions for shader objects
        if (c.pfn_vkCmdSetViewportWithCount) |setViewportWithCount| {
            setViewportWithCount(cmd, 1, &viewport);
        }
        if (c.pfn_vkCmdSetScissorWithCount) |setScissorWithCount| {
            setScissorWithCount(cmd, 1, &scissor);
        }

        //const shaderObjects = pipe.shaderObjects.items;

        var stages = [_]c.VkShaderStageFlagBits{
            c.VK_SHADER_STAGE_VERTEX_BIT,
            c.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
            c.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
            c.VK_SHADER_STAGE_GEOMETRY_BIT,
            c.VK_SHADER_STAGE_TASK_BIT_EXT,
            c.VK_SHADER_STAGE_MESH_BIT_EXT,
            c.VK_SHADER_STAGE_FRAGMENT_BIT,
        };

        // bind ALL 7 stages to ensure clean state
        var shaders = [_]c.VkShaderEXT{
            null, // Clear vertex shader for mesh
            null, // No tessellation control
            null, // No tessellation eval
            null, // No geometry
            null, // Task
            null, // Mesh
            null, // Frag
        };

        // Assign all stages to correct index
        for (pipe.shaderObjects.items) |shaderObject| {
            for (0..stages.len) |i| {
                if (shaderObject.stage == stages[i]) shaders[i] = shaderObject.handle;
            }
        }

        // Bind shader objects based on pipeline type
        switch (pipeType) {
            .graphics => {
                c.pfn_vkCmdBindShadersEXT.?(cmd, 7, &stages, &shaders);
                // Set empty vertex input state
                if (c.pfn_vkCmdSetVertexInputEXT) |setVertexInput| {
                    setVertexInput(cmd, 0, null, 0, null);
                }
                setGraphicsDynamicStates(cmd);
                // Draw
                c.vkCmdDraw(cmd, 3, 1, 0, 0);
            },
            .mesh => {
                c.pfn_vkCmdBindShadersEXT.?(cmd, 7, &stages, &shaders);
                setGraphicsDynamicStates(cmd);
                // Draw mesh tasks
                if (c.pfn_vkCmdDrawMeshTasksEXT) |drawMeshTasks| {
                    drawMeshTasks(cmd, 1, 1, 1);
                }
            },
            else => return error.UnsupportedPipelineType,
        }

        c.vkCmdEndRendering(cmd);
    }

    pub fn blitToTargets(self: *CmdManager, renderImage: *Image, targets: []const u8, swapchainMap: *CreateMapArray(Swapchain, MAX_WINDOWS, u8, MAX_WINDOWS, 0)) !void {
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

fn setGraphicsDynamicStates(cmd: c.VkCommandBuffer) void {
    if (c.pfn_vkCmdSetRasterizerDiscardEnable) |setRasterizerDiscard| setRasterizerDiscard(cmd, c.VK_FALSE);
    if (c.pfn_vkCmdSetDepthBiasEnable) |setDepthBias| setDepthBias(cmd, c.VK_FALSE);
    if (c.pfn_vkCmdSetPolygonModeEXT) |setPolygonMode| setPolygonMode(cmd, c.VK_POLYGON_MODE_FILL);
    if (c.pfn_vkCmdSetRasterizationSamplesEXT) |setRasterizationSamples| setRasterizationSamples(cmd, c.VK_SAMPLE_COUNT_1_BIT);

    if (c.pfn_vkCmdSetSampleMaskEXT) |setSampleMask| {
        const sampleMask: u32 = 0xFFFFFFFF;
        setSampleMask(cmd, c.VK_SAMPLE_COUNT_1_BIT, &sampleMask);
    }
    if (c.pfn_vkCmdSetDepthClampEnableEXT) |setDepthClamp| setDepthClamp(cmd, c.VK_FALSE);
    if (c.pfn_vkCmdSetAlphaToOneEnableEXT) |setAlphaToOne| setAlphaToOne(cmd, c.VK_FALSE);
    if (c.pfn_vkCmdSetAlphaToCoverageEnableEXT) |setAlphaToCoverage| setAlphaToCoverage(cmd, c.VK_FALSE);
    if (c.pfn_vkCmdSetLogicOpEnableEXT) |setLogicOpEnable| setLogicOpEnable(cmd, c.VK_FALSE);
    if (c.pfn_vkCmdSetCullMode) |setCullMode| setCullMode(cmd, c.VK_CULL_MODE_NONE);
    if (c.pfn_vkCmdSetFrontFace) |setFrontFace| setFrontFace(cmd, c.VK_FRONT_FACE_CLOCKWISE);
    if (c.pfn_vkCmdSetDepthTestEnable) |setDepthTest| setDepthTest(cmd, c.VK_FALSE);
    if (c.pfn_vkCmdSetDepthWriteEnable) |setDepthWrite| setDepthWrite(cmd, c.VK_FALSE);
    if (c.pfn_vkCmdSetDepthBoundsTestEnable) |setDepthBounds| setDepthBounds(cmd, c.VK_FALSE);
    if (c.pfn_vkCmdSetStencilTestEnable) |setStencilTest| setStencilTest(cmd, c.VK_FALSE);

    if (c.pfn_vkCmdSetColorBlendEnableEXT) |setColorBlend| {
        const colorBlendEnable = c.VK_FALSE;
        const colorBlendAttachments = [_]c.VkBool32{colorBlendEnable};
        setColorBlend(cmd, 0, 1, &colorBlendAttachments);
    }

    if (c.pfn_vkCmdSetColorWriteMaskEXT) |setColorWriteMask| {
        const colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT |
            c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;
        const colorWriteMasks = [_]c.VkColorComponentFlags{colorWriteMask};
        setColorWriteMask(cmd, 0, 1, &colorWriteMasks);
    }

    if (c.pfn_vkCmdSetPrimitiveTopology) |setPrimitiveTopology| setPrimitiveTopology(cmd, c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    if (c.pfn_vkCmdSetPrimitiveRestartEnable) |setPrimitiveRestart| setPrimitiveRestart(cmd, c.VK_FALSE);
}

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
