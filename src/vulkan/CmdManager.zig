const std = @import("std");
const vk = @import("vk").vk;
const vkFn = @import("vk").vkFn;
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
    gpi: vk.VkDevice,
    pool: vk.VkCommandPool,
    cmds: []vk.VkCommandBuffer,
    blitBarriers: [MAX_WINDOWS + 1]vk.VkImageMemoryBarrier2 = undefined,

    pub fn init(alloc: Allocator, context: *const @import("Context.zig").Context, maxInFlight: u32) !CmdManager {
        const gpi = context.gpi;
        const pool = try createCmdPool(gpi, context.families.graphics);

        const cmds = try alloc.alloc(vk.VkCommandBuffer, maxInFlight);
        for (0..maxInFlight) |i| {
            cmds[i] = try createCmd(gpi, pool, vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY);
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
        vk.vkDestroyCommandPool(self.gpi, self.pool, null);
    }

    pub fn beginRecording(self: *CmdManager, frameInFlight: u8) !vk.VkCommandBuffer {
        const cmd = self.cmds[frameInFlight];
        try check(vk.vkResetCommandBuffer(cmd, 0), "could not reset command buffer"); // Might be optional

        const beginInf = vk.VkCommandBufferBeginInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, //vk.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT
            .pInheritanceInfo = null,
        };
        try check(vk.vkBeginCommandBuffer(cmd, &beginInf), "could not Begin CmdBuffer");
        return self.cmds[frameInFlight];
    }

    pub fn endRecording(cmd: vk.VkCommandBuffer) !void {
        try check(vk.vkEndCommandBuffer(cmd), "Could not End Cmd Buffer");
    }

    pub fn getCmd(self: *const CmdManager, frameInFlight: u8) vk.VkCommandBuffer {
        return self.cmds[frameInFlight];
    }

    pub fn recordPass(
        cmd: vk.VkCommandBuffer,
        renderImg: *GpuImage,
        shaderObjects: []const ShaderObject,
        renderType: RenderType,
        pipeLayout: vk.VkPipelineLayout,
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
        cmd: vk.VkCommandBuffer,
        renderImg: *GpuImage,
        shaderObjects: []const ShaderObject,
        pipeLayout: vk.VkPipelineLayout,
        gpuAddress: deviceAddress,
        pushConstants: PushConstants,
    ) !void {
        const barrier = createImageMemoryBarrier2(
            vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
            vk.VK_ACCESS_2_MEMORY_WRITE_BIT | vk.VK_ACCESS_2_MEMORY_READ_BIT,
            vk.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            vk.VK_ACCESS_2_SHADER_WRITE_BIT,
            renderImg.curLayout,
            vk.VK_IMAGE_LAYOUT_GENERAL,
            renderImg.img,
            createSubresourceRange(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(cmd, &.{barrier});
        renderImg.curLayout = vk.VK_IMAGE_LAYOUT_GENERAL;

        vk.vkCmdPushConstants(cmd, pipeLayout, vk.VK_SHADER_STAGE_ALL, 0, @sizeOf(PushConstants), &pushConstants);
        bindShaderStages(cmd, shaderObjects);
        bindDescriptorBuffer(cmd, gpuAddress);
        setDescriptorBufferOffset(cmd, vk.VK_PIPELINE_BIND_POINT_COMPUTE, pipeLayout);

        vk.vkCmdDispatch(cmd, (renderImg.extent3d.width + 7) / 8, (renderImg.extent3d.height + 7) / 8, 1);
    }

    pub fn recordGraphics(
        cmd: vk.VkCommandBuffer,
        renderImg: *GpuImage,
        shaderObjects: []const ShaderObject,
        renderType: RenderType,
        pipeLayout: vk.VkPipelineLayout,
        gpuAddress: deviceAddress,
        pushConstants: PushConstants,
        shouldClear: bool,
    ) !void {
        const barrier = createImageMemoryBarrier2(
            vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
            vk.VK_ACCESS_2_MEMORY_WRITE_BIT | vk.VK_ACCESS_2_MEMORY_READ_BIT,
            vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            vk.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            renderImg.curLayout,
            vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            renderImg.img,
            createSubresourceRange(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(cmd, &.{barrier});
        renderImg.curLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

        const scissor = vk.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = renderImg.extent3d.width, .height = renderImg.extent3d.height },
        };

        const colorAttachInf = vk.VkRenderingAttachmentInfo{
            .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = renderImg.view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .loadOp = if (shouldClear) vk.VK_ATTACHMENT_LOAD_OP_CLEAR else vk.VK_ATTACHMENT_LOAD_OP_LOAD,
            .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
            .clearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.1, 1.0 } } },
        };

        const renderInf = vk.VkRenderingInfo{
            .sType = vk.VK_STRUCTURE_TYPE_RENDERING_INFO,
            .flags = 0,
            .renderArea = scissor,
            .layerCount = 1,
            .colorAttachmentCount = 1,
            .pColorAttachments = &colorAttachInf,
            .pDepthAttachment = null,
            .pStencilAttachment = null,
        };
        vk.vkCmdBeginRendering(cmd, &renderInf);

        const viewport = vk.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(renderImg.extent3d.width),
            .height = @floatFromInt(renderImg.extent3d.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        vkFn.vkCmdSetViewportWithCount.?(cmd, 1, &viewport);
        vkFn.vkCmdSetScissorWithCount.?(cmd, 1, &scissor);

        vk.vkCmdPushConstants(cmd, pipeLayout, vk.VK_SHADER_STAGE_ALL, 0, @sizeOf(PushConstants), &pushConstants);
        bindShaderStages(cmd, shaderObjects);
        bindDescriptorBuffer(cmd, gpuAddress);
        setDescriptorBufferOffset(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeLayout);
        setGraphicsDynamicStates(cmd);

        switch (renderType) {
            .graphicsPass => {
                vkFn.vkCmdSetVertexInputEXT.?(cmd, 0, null, 0, null); // Currently empty vertex input state
                vk.vkCmdDraw(cmd, 3, 1, 0, 0);
            },
            .meshPass, .taskMeshPass => vkFn.vkCmdDrawMeshTasksEXT.?(cmd, 1, 1, 1),
            else => return error.UnsupportedPipelineType,
        }
        vk.vkCmdEndRendering(cmd);
    }

    pub fn transitionToPresent(cmd: vk.VkCommandBuffer, swapchain: *SwapchainManager.Swapchain) void {
        const barrier = createImageMemoryBarrier2(
            vk.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
            0,
            vk.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
            0,
            vk.VK_IMAGE_LAYOUT_UNDEFINED, // Not important what it was
            vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, // Must be SRC for presentation
            swapchain.images[swapchain.curIndex],
            createSubresourceRange(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        );
        createPipelineBarriers2(cmd, &.{barrier});
    }

    pub fn recordSwapchainBlits(cmd: vk.VkCommandBuffer, renderImages: []?GpuImage, targets: []const u32, swapchainMap: *SwapchainManager.SwapchainMap) !void {
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
                vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                vk.VK_ACCESS_2_MEMORY_WRITE_BIT,
                vk.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
                vk.VK_ACCESS_2_TRANSFER_READ_BIT,
                srcImgPtr.curLayout,
                vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                srcImgPtr.img,
                createSubresourceRange(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
            );
            // 2. BARRIER: Transition Dest Swapchain (Undefined -> Transfer Dst)
            const dstBarrier = createImageMemoryBarrier2(
                vk.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
                0,
                vk.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
                vk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
                vk.VK_IMAGE_LAYOUT_UNDEFINED,
                vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                swapchain.images[swapchain.curIndex],
                createSubresourceRange(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
            );
            createPipelineBarriers2(cmd, &.{ srcBarrier, dstBarrier });

            srcImgPtr.curLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;

            // 3. CALCULATE BLIT OFFSETS
            var srcOffsets: [2]vk.VkOffset3D = undefined;
            var dstOffsets: [2]vk.VkOffset3D = undefined;

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

fn bindDescriptorBuffer(cmd: vk.VkCommandBuffer, gpuAddress: deviceAddress) void {
    const bufferBindingInf = vk.VkDescriptorBufferBindingInfoEXT{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
        .address = gpuAddress,
        .usage = vk.VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT,
    };
    vkFn.vkCmdBindDescriptorBuffersEXT.?(cmd, 1, &bufferBindingInf);
}

fn setDescriptorBufferOffset(cmd: vk.VkCommandBuffer, bindPoint: vk.VkPipelineBindPoint, pipeLayout: vk.VkPipelineLayout) void {
    const bufferIndex: u32 = 0;
    const descOffset: vk.VkDeviceSize = 0;
    vkFn.vkCmdSetDescriptorBufferOffsetsEXT.?(cmd, bindPoint, pipeLayout, 0, 1, &bufferIndex, &descOffset);
}

fn setGraphicsDynamicStates(cmd: vk.VkCommandBuffer) void {
    vkFn.vkCmdSetRasterizerDiscardEnable.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetDepthBiasEnable.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetPolygonModeEXT.?(cmd, vk.VK_POLYGON_MODE_FILL);
    vkFn.vkCmdSetRasterizationSamplesEXT.?(cmd, vk.VK_SAMPLE_COUNT_1_BIT);

    const sampleMask: u32 = 0xFFFFFFFF;
    vkFn.vkCmdSetSampleMaskEXT.?(cmd, vk.VK_SAMPLE_COUNT_1_BIT, &sampleMask);

    vkFn.vkCmdSetDepthClampEnableEXT.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetAlphaToOneEnableEXT.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetAlphaToCoverageEnableEXT.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetLogicOpEnableEXT.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetCullMode.?(cmd, vk.VK_CULL_MODE_FRONT_BIT); // CULL_MODE_BACK_BIT looking inside the grid
    vkFn.vkCmdSetFrontFace.?(cmd, vk.VK_FRONT_FACE_CLOCKWISE);
    vkFn.vkCmdSetDepthTestEnable.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetDepthWriteEnable.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetDepthBoundsTestEnable.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetStencilTestEnable.?(cmd, vk.VK_FALSE);

    const colorBlendEnable = vk.VK_TRUE;
    const colorBlendAttachments = [_]vk.VkBool32{colorBlendEnable};
    vkFn.vkCmdSetColorBlendEnableEXT.?(cmd, 0, 1, &colorBlendAttachments);

    // 2. SET BLEND EQUATION (Standard Transparency)
    const blendEquation = vk.VkColorBlendEquationEXT{
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA, // Take Shader Alpha
        .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, // Take 1-Alpha from Background
        .colorBlendOp = vk.VK_BLEND_OP_ADD, // Add them
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = vk.VK_BLEND_OP_ADD,
    };
    const equations = [_]vk.VkColorBlendEquationEXT{blendEquation};

    // You need to call this to configure the math!
    vkFn.vkCmdSetColorBlendEquationEXT.?(cmd, 0, 1, &equations);

    const colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT;
    const colorWriteMasks = [_]vk.VkColorComponentFlags{colorWriteMask};
    vkFn.vkCmdSetColorWriteMaskEXT.?(cmd, 0, 1, &colorWriteMasks);

    vkFn.vkCmdSetPrimitiveTopology.?(cmd, vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    vkFn.vkCmdSetPrimitiveRestartEnable.?(cmd, vk.VK_FALSE);
}

fn createCmd(gpi: vk.VkDevice, pool: vk.VkCommandPool, level: vk.VkCommandBufferLevel) !vk.VkCommandBuffer {
    const allocInf = vk.VkCommandBufferAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = level,
        .commandBufferCount = 1,
    };
    var cmd: vk.VkCommandBuffer = undefined;
    try check(vk.vkAllocateCommandBuffers(gpi, &allocInf, &cmd), "Could not create Cmd Buffer");
    return cmd;
}

fn createCmdPool(gpi: vk.VkDevice, familyIndex: u32) !vk.VkCommandPool {
    const poolInf = vk.VkCommandPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT | vk.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
        .queueFamilyIndex = familyIndex,
    };
    var pool: vk.VkCommandPool = undefined;
    try check(vk.vkCreateCommandPool(gpi, &poolInf, null, &pool), "Could not create Cmd Pool");
    return pool;
}

fn bindShaderStages(cmd: vk.VkCommandBuffer, shaderObjects: []const ShaderObject) void {
    var stages = [_]ShaderStage{ .compute, .vertex, .tessControl, .tessEval, .geometry, .task, .mesh, .frag };
    var shaders = [_]vk.VkShaderEXT{ null, null, null, null, null, null, null, null }; // clean state
    // Assign stages to correct index
    for (shaderObjects) |shaderObject| {
        for (0..stages.len) |i| {
            if (shaderObject.stage == stages[i]) shaders[i] = shaderObject.handle;
        }
    }
    vkFn.vkCmdBindShadersEXT.?(cmd, 8, @ptrCast(&stages), &shaders);
}

fn createPipelineBarriers2(cmd: vk.VkCommandBuffer, barriers: []const vk.VkImageMemoryBarrier2) void {
    const depInf = vk.VkDependencyInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = @intCast(barriers.len),
        .pImageMemoryBarriers = barriers.ptr,
    };
    vk.vkCmdPipelineBarrier2(cmd, &depInf);
}

fn createSubresourceRange(mask: u32, mipLevel: u32, levelCount: u32, arrayLayer: u32, layerCount: u32) vk.VkImageSubresourceRange {
    return vk.VkImageSubresourceRange{
        .aspectMask = mask,
        .baseMipLevel = mipLevel,
        .levelCount = levelCount,
        .baseArrayLayer = arrayLayer,
        .layerCount = layerCount,
    };
}

fn createSubresourceLayers(mask: u32, mipLevel: u32, arrayLayer: u32, layerCount: u32) vk.VkImageSubresourceLayers {
    return vk.VkImageSubresourceLayers{ .aspectMask = mask, .mipLevel = mipLevel, .baseArrayLayer = arrayLayer, .layerCount = layerCount };
}

fn createImageMemoryBarrier2(
    srcStage: u64,
    srcAccess: u64,
    dstStage: u64,
    dstAccess: u64,
    oldLayout: u32,
    newLayout: u32,
    img: vk.VkImage,
    subResRange: vk.VkImageSubresourceRange,
) vk.VkImageMemoryBarrier2 {
    return vk.VkImageMemoryBarrier2{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = srcStage,
        .srcAccessMask = srcAccess,
        .dstStageMask = dstStage,
        .dstAccessMask = dstAccess,
        .oldLayout = oldLayout,
        .newLayout = newLayout,
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = img,
        .subresourceRange = subResRange,
    };
}

pub fn copyImageToImage(cmd: vk.VkCommandBuffer, srcImg: vk.VkImage, srcOffsets: [2]vk.VkOffset3D, dstImg: vk.VkImage, dstOffsets: [2]vk.VkOffset3D) void {
    const blitRegion = vk.VkImageBlit2{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_BLIT_2,
        .srcSubresource = createSubresourceLayers(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
        .srcOffsets = srcOffsets,
        .dstSubresource = createSubresourceLayers(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
        .dstOffsets = dstOffsets,
    };
    const blitInf = vk.VkBlitImageInfo2{
        .sType = vk.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2,
        .dstImage = dstImg,
        .dstImageLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .srcImage = srcImg,
        .srcImageLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .filter = if (config.RENDER_IMG_STRETCH) vk.VK_FILTER_LINEAR else vk.VK_FILTER_NEAREST, // Linear for stretch, Nearest for pixel-perfect
        .regionCount = 1,
        .pRegions = &blitRegion,
    };
    vk.vkCmdBlitImage2(cmd, &blitInf);
}
