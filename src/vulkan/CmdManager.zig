const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const GpuImage = @import("ResourceManager.zig").GpuImage;
const SwapchainManager = @import("SwapchainManager.zig");
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const ShaderStage = @import("ShaderObject.zig").ShaderStage;
const RenderType = @import("../config.zig").RenderType;
const PushConstants = @import("ShaderManager.zig").PushConstants;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const deviceAddress = @import("ResourceManager.zig").GpuBuffer.deviceAddress;
const MAX_WINDOWS = @import("../config.zig").MAX_WINDOWS;
const check = @import("error.zig").check;
const config = @import("../config.zig");

pub const CmdManager = struct {
    alloc: Allocator,
    gpi: c.VkDevice,
    pool: c.VkCommandPool,
    cmds: []c.VkCommandBuffer,
    blitBarriers: [MAX_WINDOWS + 1]c.VkImageMemoryBarrier2 = undefined,

    pub fn init(alloc: Allocator, context: *const @import("Context.zig").Context, maxInFlight: u32) !CmdManager {
        const gpi = context.gpi;
        const pool = try createCmdPool(gpi, context.families.graphics);

        const cmds = try alloc.alloc(c.VkCommandBuffer, maxInFlight);
        for (0..maxInFlight) |i| {
            cmds[i] = try createCmd(gpi, pool, c.VK_COMMAND_BUFFER_LEVEL_PRIMARY);
        }

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .pool = pool,
            .cmds = cmds,
        };
    }

    pub fn deinit(self: *CmdManager) void {
        self.alloc.free(self.cmds);
        c.vkDestroyCommandPool(self.gpi, self.pool, null);
    }

    pub fn beginRecording(self: *CmdManager, frameInFlight: u8) !c.VkCommandBuffer {
        const cmd = self.cmds[frameInFlight];
        try check(c.vkResetCommandBuffer(cmd, 0), "could not reset command buffer"); // Might be optional

        const beginInf = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, //c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT
            .pInheritanceInfo = null,
        };
        try check(c.vkBeginCommandBuffer(cmd, &beginInf), "could not Begin CmdBuffer");
        return self.cmds[frameInFlight];
    }

    pub fn endRecording(cmd: c.VkCommandBuffer) !void {
        try check(c.vkEndCommandBuffer(cmd), "Could not End Cmd Buffer");
    }

    pub fn getCmd(self: *const CmdManager, frameInFlight: u8) c.VkCommandBuffer {
        return self.cmds[frameInFlight];
    }

    pub fn recordPass(
        cmd: c.VkCommandBuffer,
        renderImg: *GpuImage,
        shaderObjects: []const ShaderObject,
        renderType: RenderType,
        pipeLayout: c.VkPipelineLayout,
        gpuAddress: deviceAddress,
        pushConstants: PushConstants,
        shouldClear: bool,
    ) !void {
        switch (renderType) {
            .computePass => try recordCompute(cmd, renderImg, shaderObjects, pipeLayout, gpuAddress, pushConstants),
            .graphicsPass, .meshPass, .taskMeshPass => try recordGraphics(cmd, renderImg, shaderObjects, renderType, pipeLayout, gpuAddress, pushConstants, shouldClear),
            else => std.debug.print("Renderer: {s} has no Command Recording yet\n", .{@tagName(renderType)}),
        }
    }

    pub fn recordCompute(
        cmd: c.VkCommandBuffer,
        renderImg: *GpuImage,
        shaderObjects: []const ShaderObject,
        pipeLayout: c.VkPipelineLayout,
        gpuAddress: deviceAddress,
        pushConstants: PushConstants,
    ) !void {
        const barrier = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
            c.VK_ACCESS_2_MEMORY_WRITE_BIT | c.VK_ACCESS_2_MEMORY_READ_BIT,
            c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            c.VK_ACCESS_2_SHADER_WRITE_BIT,
            renderImg.curLayout,
            c.VK_IMAGE_LAYOUT_GENERAL,
            renderImg.img,
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(cmd, &.{barrier});
        renderImg.curLayout = c.VK_IMAGE_LAYOUT_GENERAL;

        c.vkCmdPushConstants(cmd, pipeLayout, c.VK_SHADER_STAGE_ALL, 0, @sizeOf(PushConstants), &pushConstants);
        bindShaderStages(cmd, shaderObjects);
        bindDescriptorBuffer(cmd, gpuAddress);
        setDescriptorBufferOffset(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, pipeLayout);

        c.vkCmdDispatch(cmd, (renderImg.extent3d.width + 7) / 8, (renderImg.extent3d.height + 7) / 8, 1);
    }

    pub fn recordGraphics(
        cmd: c.VkCommandBuffer,
        renderImg: *GpuImage,
        shaderObjects: []const ShaderObject,
        renderType: RenderType,
        pipeLayout: c.VkPipelineLayout,
        gpuAddress: deviceAddress,
        pushConstants: PushConstants,
        shouldClear: bool,
    ) !void {
        const barrier = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
            c.VK_ACCESS_2_MEMORY_WRITE_BIT | c.VK_ACCESS_2_MEMORY_READ_BIT,
            c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            renderImg.curLayout,
            c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            renderImg.img,
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(cmd, &.{barrier});
        renderImg.curLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

        const scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = renderImg.extent3d.width, .height = renderImg.extent3d.height },
        };

        const colorAttachInf = c.VkRenderingAttachmentInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = renderImg.view,
            .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .loadOp = if (shouldClear) c.VK_ATTACHMENT_LOAD_OP_CLEAR else c.VK_ATTACHMENT_LOAD_OP_LOAD,
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

        const viewport = c.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(renderImg.extent3d.width),
            .height = @floatFromInt(renderImg.extent3d.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        c.pfn_vkCmdSetViewportWithCount.?(cmd, 1, &viewport);
        c.pfn_vkCmdSetScissorWithCount.?(cmd, 1, &scissor);

        c.vkCmdPushConstants(cmd, pipeLayout, c.VK_SHADER_STAGE_ALL, 0, @sizeOf(PushConstants), &pushConstants);
        bindShaderStages(cmd, shaderObjects);
        bindDescriptorBuffer(cmd, gpuAddress);
        setDescriptorBufferOffset(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeLayout);
        setGraphicsDynamicStates(cmd);

        switch (renderType) {
            .graphicsPass => {
                c.pfn_vkCmdSetVertexInputEXT.?(cmd, 0, null, 0, null); // Currently empty vertex input state
                c.vkCmdDraw(cmd, 3, 1, 0, 0);
            },
            .meshPass, .taskMeshPass => c.pfn_vkCmdDrawMeshTasksEXT.?(cmd, 1, 1, 1),
            else => return error.UnsupportedPipelineType,
        }
        c.vkCmdEndRendering(cmd);
    }

    pub fn transitionToPresent(cmd: c.VkCommandBuffer, swapchain: *SwapchainManager.Swapchain) void {
        const barrier = createImageMemoryBarrier2(
            c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
            0,
            c.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
            0,
            c.VK_IMAGE_LAYOUT_UNDEFINED, // Not important what it was
            c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, // Must be SRC for presentation
            swapchain.images[swapchain.curIndex],
            createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(cmd, &.{barrier});
    }

    pub fn recordSwapchainBlits(cmd: c.VkCommandBuffer, renderImages: []?GpuImage, targets: []const u32, swapchainMap: *SwapchainManager.SwapchainMap) !void {
        for (targets) |swapchainIndex| {
            const swapchain = swapchainMap.getPtrAtIndex(swapchainIndex);
            const imgID = swapchain.renderId;

            if (renderImages[imgID] == null) {
                std.debug.print("Error: Window wants RenderID {} but it is null\n", .{imgID});
                continue;
            }
            var srcImgPtr = &renderImages[imgID].?;

            // 1. BARRIER: Transition Source Image (Color/General -> Transfer Src)
            const srcBarrier = createImageMemoryBarrier2(
                c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                c.VK_ACCESS_2_MEMORY_WRITE_BIT,
                c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
                c.VK_ACCESS_2_TRANSFER_READ_BIT,
                srcImgPtr.curLayout,
                c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                srcImgPtr.img,
                createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
            );
            // 2. BARRIER: Transition Dest Swapchain (Undefined -> Transfer Dst)
            const dstBarrier = createImageMemoryBarrier2(
                c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
                0,
                c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
                c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
                c.VK_IMAGE_LAYOUT_UNDEFINED,
                c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                swapchain.images[swapchain.curIndex],
                createSubresourceRange(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
            );
            createPipelineBarriers2(cmd, &.{ srcBarrier, dstBarrier });

            srcImgPtr.curLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;

            // 3. CALCULATE BLIT OFFSETS
            var srcOffsets: [2]c.VkOffset3D = undefined;
            var dstOffsets: [2]c.VkOffset3D = undefined;

            if (config.RENDER_IMG_STRETCH) {
                // Stretch: Source is full image, Dest is full window
                srcOffsets[0] = .{ .x = 0, .y = 0, .z = 0 };
                srcOffsets[1] = .{ .x = @intCast(srcImgPtr.extent3d.width), .y = @intCast(srcImgPtr.extent3d.height), .z = 1 };

                dstOffsets[0] = .{ .x = 0, .y = 0, .z = 0 };
                dstOffsets[1] = .{ .x = @intCast(swapchain.extent.width), .y = @intCast(swapchain.extent.height), .z = 1 };
            } else {
                // No Stretch (Center / Crop)
                const srcW: i32 = @intCast(srcImgPtr.extent3d.width);
                const srcH: i32 = @intCast(srcImgPtr.extent3d.height);
                const winW: i32 = @intCast(swapchain.extent.width);
                const winH: i32 = @intCast(swapchain.extent.height);

                // Determine the size of the region to copy (the smaller of the two dimensions)
                const blitW = @min(srcW, winW);
                const blitH = @min(srcH, winH);

                // Center the region on the SOURCE
                // If Source < Window, this is 0. If Source > Window, this crops the center.
                const srcX = @divFloor(srcW - blitW, 2);
                const srcY = @divFloor(srcH - blitH, 2);

                srcOffsets[0] = .{ .x = srcX, .y = srcY, .z = 0 };
                srcOffsets[1] = .{ .x = srcX + blitW, .y = srcY + blitH, .z = 1 };

                // Center the region on the DESTINATION
                // If Window > Source, this centers the image on screen. If Window < Source, this is 0.
                const dstX = @divFloor(winW - blitW, 2);
                const dstY = @divFloor(winH - blitH, 2);

                dstOffsets[0] = .{ .x = dstX, .y = dstY, .z = 0 };
                dstOffsets[1] = .{ .x = dstX + blitW, .y = dstY + blitH, .z = 1 };
            }
            // 4. BLIT
            copyImageToImage(cmd, srcImgPtr.img, srcOffsets, swapchain.images[swapchain.curIndex], dstOffsets);
            // 5. Transition Dest Swapchain to Present
            transitionToPresent(cmd, swapchain);
        }
    }
};

fn bindDescriptorBuffer(cmd: c.VkCommandBuffer, gpuAddress: deviceAddress) void {
    const bufferBindingInf = c.VkDescriptorBufferBindingInfoEXT{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
        .address = gpuAddress,
        .usage = c.VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT,
    };
    c.pfn_vkCmdBindDescriptorBuffersEXT.?(cmd, 1, &bufferBindingInf);
}

fn setDescriptorBufferOffset(cmd: c.VkCommandBuffer, bindPoint: c.VkPipelineBindPoint, pipeLayout: c.VkPipelineLayout) void {
    const bufferIndex: u32 = 0;
    const descOffset: c.VkDeviceSize = 0;
    c.pfn_vkCmdSetDescriptorBufferOffsetsEXT.?(cmd, bindPoint, pipeLayout, 0, 1, &bufferIndex, &descOffset);
}

fn setGraphicsDynamicStates(cmd: c.VkCommandBuffer) void {
    c.pfn_vkCmdSetRasterizerDiscardEnable.?(cmd, c.VK_FALSE);
    c.pfn_vkCmdSetDepthBiasEnable.?(cmd, c.VK_FALSE);
    c.pfn_vkCmdSetPolygonModeEXT.?(cmd, c.VK_POLYGON_MODE_FILL);
    c.pfn_vkCmdSetRasterizationSamplesEXT.?(cmd, c.VK_SAMPLE_COUNT_1_BIT);

    const sampleMask: u32 = 0xFFFFFFFF;
    c.pfn_vkCmdSetSampleMaskEXT.?(cmd, c.VK_SAMPLE_COUNT_1_BIT, &sampleMask);

    c.pfn_vkCmdSetDepthClampEnableEXT.?(cmd, c.VK_FALSE);
    c.pfn_vkCmdSetAlphaToOneEnableEXT.?(cmd, c.VK_FALSE);
    c.pfn_vkCmdSetAlphaToCoverageEnableEXT.?(cmd, c.VK_FALSE);
    c.pfn_vkCmdSetLogicOpEnableEXT.?(cmd, c.VK_FALSE);
    c.pfn_vkCmdSetCullMode.?(cmd, c.VK_CULL_MODE_FRONT_BIT); // CULL_MODE_BACK_BIT looking inside the grid
    c.pfn_vkCmdSetFrontFace.?(cmd, c.VK_FRONT_FACE_CLOCKWISE);
    c.pfn_vkCmdSetDepthTestEnable.?(cmd, c.VK_FALSE);
    c.pfn_vkCmdSetDepthWriteEnable.?(cmd, c.VK_FALSE);
    c.pfn_vkCmdSetDepthBoundsTestEnable.?(cmd, c.VK_FALSE);
    c.pfn_vkCmdSetStencilTestEnable.?(cmd, c.VK_FALSE);

    const colorBlendEnable = c.VK_TRUE;
    const colorBlendAttachments = [_]c.VkBool32{colorBlendEnable};
    c.pfn_vkCmdSetColorBlendEnableEXT.?(cmd, 0, 1, &colorBlendAttachments);

    // 2. SET BLEND EQUATION (Standard Transparency)
    const blendEquation = c.VkColorBlendEquationEXT{
        .srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA, // Take Shader Alpha
        .dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, // Take 1-Alpha from Background
        .colorBlendOp = c.VK_BLEND_OP_ADD, // Add them
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
    };
    const equations = [_]c.VkColorBlendEquationEXT{blendEquation};

    // You need to call this to configure the math!
    c.pfn_vkCmdSetColorBlendEquationEXT.?(cmd, 0, 1, &equations);

    const colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;
    const colorWriteMasks = [_]c.VkColorComponentFlags{colorWriteMask};
    c.pfn_vkCmdSetColorWriteMaskEXT.?(cmd, 0, 1, &colorWriteMasks);

    c.pfn_vkCmdSetPrimitiveTopology.?(cmd, c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    c.pfn_vkCmdSetPrimitiveRestartEnable.?(cmd, c.VK_FALSE);
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

fn bindShaderStages(cmd: c.VkCommandBuffer, shaderObjects: []const ShaderObject) void {
    var stages = [_]ShaderStage{ .compute, .vertex, .tessControl, .tessEval, .geometry, .task, .mesh, .frag };
    var shaders = [_]c.VkShaderEXT{ null, null, null, null, null, null, null, null }; // clean state
    // Assign stages to correct index
    for (shaderObjects) |shaderObject| {
        for (0..stages.len) |i| {
            if (shaderObject.stage == stages[i]) shaders[i] = shaderObject.handle;
        }
    }
    c.pfn_vkCmdBindShadersEXT.?(cmd, 8, @ptrCast(&stages), &shaders);
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
    img: c.VkImage,
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
        .image = img,
        .subresourceRange = subResRange,
    };
}

pub fn copyImageToImage(cmd: c.VkCommandBuffer, srcImg: c.VkImage, srcOffsets: [2]c.VkOffset3D, dstImg: c.VkImage, dstOffsets: [2]c.VkOffset3D) void {
    const blitRegion = c.VkImageBlit2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_BLIT_2,
        .srcSubresource = createSubresourceLayers(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
        .srcOffsets = srcOffsets,
        .dstSubresource = createSubresourceLayers(c.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
        .dstOffsets = dstOffsets,
    };
    const blitInf = c.VkBlitImageInfo2{
        .sType = c.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2,
        .dstImage = dstImg,
        .dstImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .srcImage = srcImg,
        .srcImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .filter = if (config.RENDER_IMG_STRETCH) c.VK_FILTER_LINEAR else c.VK_FILTER_NEAREST, // Linear for stretch, Nearest for pixel-perfect
        .regionCount = 1,
        .pRegions = &blitRegion,
    };
    c.vkCmdBlitImage2(cmd, &blitInf);
}
