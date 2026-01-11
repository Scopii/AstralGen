const PendingTransfer = @import("../systems/ResourceManager.zig").Transfer;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const GraphicState = @import("GraphicState.zig").GraphicState;
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const vh = @import("../systems/Helpers.zig");

pub const Command = struct {
    handle: vk.VkCommandBuffer,

    pub fn init(cmd: vk.VkCommandBuffer) !Command {
        return .{ .handle = cmd };
    }

    pub fn begin(self: *const Command) !void {
        const beginInf = vk.VkCommandBufferBeginInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, //vk.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT
            .pInheritanceInfo = null,
        };
        try vh.check(vk.vkBeginCommandBuffer(self.handle, &beginInf), "could not Begin CmdBuffer");
    }

    pub fn end(self: *const Command) !void {
        try vh.check(vk.vkEndCommandBuffer(self.handle), "Could not End CmdBuffer");
    }

    pub fn writeTimestamp(self: *const Command, pool: vk.VkQueryPool, stage: vk.VkPipelineStageFlagBits2, queryIndex: u32) void {
        vk.vkCmdWriteTimestamp2(self.handle, stage, pool, queryIndex);
    }

    pub fn bakeBarriers(self: *const Command, imgBarriers: []const vk.VkImageMemoryBarrier2, bufBarriers: []const vk.VkBufferMemoryBarrier2) void {
        const depInf = vk.VkDependencyInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .imageMemoryBarrierCount = @intCast(imgBarriers.len),
            .pImageMemoryBarriers = imgBarriers.ptr,
            .bufferMemoryBarrierCount = @intCast(bufBarriers.len),
            .pBufferMemoryBarriers = bufBarriers.ptr,
        };
        vk.vkCmdPipelineBarrier2(self.handle, &depInf);
    }

    pub fn setPushConstants(self: *const Command, layout: vk.VkPipelineLayout, stageFlags: vk.VkShaderStageFlags, offset: u32, size: u32, pcs: ?*const anyopaque) void {
        vk.vkCmdPushConstants(self.handle, layout, stageFlags, offset, size, pcs);
    }

    pub fn setEmptyVertexInput(self: *const Command) void {
        vkFn.vkCmdSetVertexInputEXT.?(self.handle, 0, null, 0, null);
    }

    pub fn draw(self: *const Command, vertexCount: u32, instanceCount: u32, firstVertex: u32, firstInstance: u32) void {
        vk.vkCmdDraw(self.handle, vertexCount, instanceCount, firstVertex, firstInstance);
    }

    pub fn drawIndirect(self: *const Command, buffer: vk.VkBuffer, offset: u64, drawCount: u32, stride: u32) void {
        vk.vkCmdDrawIndirect(self.handle, buffer, offset, drawCount, stride);
    }

    pub fn drawMeshTasks(self: *const Command, workgroupsX: u32, workgroupsY: u32, workgroupsZ: u32) void {
        vkFn.vkCmdDrawMeshTasksEXT.?(self.handle, workgroupsX, workgroupsY, workgroupsZ);
    }

    pub fn drawMeshTasksIndirect(self: *const Command, buffer: vk.VkBuffer, offset: u64, drawCount: u32, stride: u32) void {
        vkFn.vkCmdDrawMeshTasksIndirectEXT.?(self.handle, buffer, offset, drawCount, stride);
    }

    pub fn endRendering(self: *const Command) void {
        vk.vkCmdEndRendering(self.handle);
    }

    pub fn bindDescriptorBuffer(self: *const Command, gpuAddress: u64) void {
        const bufferBindingInf = vk.VkDescriptorBufferBindingInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
            .address = gpuAddress,
            .usage = vk.VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT,
        };
        vkFn.vkCmdBindDescriptorBuffersEXT.?(self.handle, 1, &bufferBindingInf);
    }

    pub fn setDescriptorBufferOffset(self: *const Command, bindPoint: vk.VkPipelineBindPoint, pipeLayout: vk.VkPipelineLayout) void {
        const bufferIndex: u32 = 0;
        const descOffset: vk.VkDeviceSize = 0;
        vkFn.vkCmdSetDescriptorBufferOffsetsEXT.?(self.handle, bindPoint, pipeLayout, 0, 1, &bufferIndex, &descOffset);
    }

    pub fn copyImageToImage(self: *const Command, srcImg: vk.VkImage, srcExtent: vk.VkExtent3D, dstImg: vk.VkImage, dstExtent: vk.VkExtent3D, stretch: bool) void {
        const blitOffsets = calculateBlitOffsets(srcExtent, dstExtent, stretch);

        const blitRegion = vk.VkImageBlit2{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_BLIT_2,
            .srcSubresource = createSubresourceLayers(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
            .srcOffsets = blitOffsets.srcOffsets,
            .dstSubresource = createSubresourceLayers(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
            .dstOffsets = blitOffsets.dstOffsets,
        };
        const blitInf = vk.VkBlitImageInfo2{
            .sType = vk.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2,
            .dstImage = dstImg,
            .dstImageLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcImage = srcImg,
            .srcImageLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .filter = if (stretch) vk.VK_FILTER_LINEAR else vk.VK_FILTER_NEAREST, // Linear for stretch, Nearest for pixel-perfect
            .regionCount = 1,
            .pRegions = &blitRegion,
        };
        vk.vkCmdBlitImage2(self.handle, &blitInf);
    }

    pub fn beginRendering(
        self: *const Command,
        width: u32,
        height: u32,
        colorInfs: []vk.VkRenderingAttachmentInfo,
        depthInf: ?vk.VkRenderingAttachmentInfo,
        stencilInf: ?vk.VkRenderingAttachmentInfo,
    ) void {
        const viewport = vk.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        vkFn.vkCmdSetViewportWithCount.?(self.handle, 1, &viewport);

        const scissor = vk.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = width, .height = height },
        };

        vkFn.vkCmdSetScissorWithCount.?(self.handle, 1, &scissor);

        const renderInf = vk.VkRenderingInfo{
            .sType = vk.VK_STRUCTURE_TYPE_RENDERING_INFO,
            .flags = 0,
            .renderArea = scissor,
            .layerCount = 1,
            .colorAttachmentCount = @intCast(colorInfs.len),
            .pColorAttachments = colorInfs.ptr,
            .pDepthAttachment = if (depthInf != null) &depthInf.? else null,
            .pStencilAttachment = if (stencilInf != null) &stencilInf.? else null,
        };

        vk.vkCmdBeginRendering(self.handle, &renderInf);
    }

    pub fn bindShaders(self: *const Command, shaders: []const ShaderObject) void {
        const allStages = [_]vk.VkShaderStageFlagBits{
            vk.VK_SHADER_STAGE_VERTEX_BIT,
            vk.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
            vk.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
            vk.VK_SHADER_STAGE_GEOMETRY_BIT,
            vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            vk.VK_SHADER_STAGE_COMPUTE_BIT,
            vk.VK_SHADER_STAGE_TASK_BIT_EXT,
            vk.VK_SHADER_STAGE_MESH_BIT_EXT,
        };
        var handles: [8]vk.VkShaderEXT = .{null} ** 8;

        for (shaders) |shader| {
            const activeStageBit = vh.getShaderBit(shader.stage);

            for (0..8) |i| {
                if (allStages[i] == activeStageBit) {
                    handles[i] = shader.handle;
                    break;
                }
            }
        }
        vkFn.vkCmdBindShadersEXT.?(self.handle, 8, &allStages, &handles);
    }

    pub fn dispatch(self: *const Command, groupCountX: u32, groupCountY: u32, groupCountZ: u32) void {
        vk.vkCmdDispatch(self.handle, groupCountX, groupCountY, groupCountZ);
    }

    pub fn fillBuffer(self: *const Command, buffer: vk.VkBuffer, offset: u64, size: u64, data: u32) void {
        vk.vkCmdFillBuffer(self.handle, buffer, offset, size, data);
    }

    pub fn copyBuffer(self: *const Command, srcBuffer: vk.VkBuffer, transfer: *const PendingTransfer, dstBuffer: vk.VkBuffer) void {
        const copy = vk.VkBufferCopy{ .srcOffset = transfer.srcOffset, .dstOffset = 0, .size = transfer.size };
        vk.vkCmdCopyBuffer(self.handle, srcBuffer, dstBuffer, 1, &copy);
    }

    pub fn setGraphicsState(self: *const Command, state: GraphicState) void {
        const cmd = self.handle;

        // Rasterization & Geometry
        vkFn.vkCmdSetPolygonModeEXT.?(cmd, state.polygonMode);
        vkFn.vkCmdSetCullMode.?(cmd, state.cullMode);
        vkFn.vkCmdSetFrontFace.?(cmd, state.frontFace);
        vkFn.vkCmdSetPrimitiveTopology.?(cmd, state.topology);

        vkFn.vkCmdSetPrimitiveRestartEnable.?(cmd, state.primitiveRestart);
        vkFn.vkCmdSetRasterizerDiscardEnable.?(cmd, state.rasterDiscard);
        vkFn.vkCmdSetRasterizationSamplesEXT.?(cmd, state.rasterSamples);

        const sampleMask: u32 = state.sample.sampleMask;
        vkFn.vkCmdSetSampleMaskEXT.?(cmd, state.sample.sampling, &sampleMask);

        // Depth & Stencil
        vkFn.vkCmdSetDepthBoundsTestEnable.?(cmd, state.depthBoundsTest);
        vkFn.vkCmdSetDepthBiasEnable.?(cmd, state.depthBias);
        vkFn.vkCmdSetDepthClampEnableEXT.?(cmd, state.depthClamp);

        vkFn.vkCmdSetDepthTestEnable.?(cmd, state.depthTest);
        vkFn.vkCmdSetDepthWriteEnable.?(cmd, state.depthWrite);
        vkFn.vkCmdSetDepthCompareOp.?(cmd, state.depthCompare);
        vkFn.vkCmdSetDepthBias.?(cmd, state.depthValues.constant, state.depthValues.clamp, state.depthValues.slope);

        vkFn.vkCmdSetStencilTestEnable.?(cmd, state.stencilTest);
        vkFn.vkCmdSetStencilOp.?(cmd, state.stencilOp[0], state.stencilOp[1], state.stencilOp[2], state.stencilOp[3], state.stencilOp[4]);
        vkFn.vkCmdSetStencilCompareMask.?(cmd, state.stencilCompare.faceMask, state.stencilCompare.mask);
        vkFn.vkCmdSetStencilWriteMask.?(cmd, state.stencilWrite.faceMask, state.stencilWrite.mask);
        vkFn.vkCmdSetStencilReference.?(cmd, state.stencilReference.faceMask, state.stencilReference.mask);

        // Color & Blending
        const blendEnable = state.colorBlend;
        const colorBlendAttachments = [_]vk.VkBool32{blendEnable} ** 8;
        vkFn.vkCmdSetColorBlendEnableEXT.?(cmd, 0, 8, &colorBlendAttachments);

        const blendEquation = vk.VkColorBlendEquationEXT{
            .srcColorBlendFactor = state.colorBlendEquation.srcColor,
            .dstColorBlendFactor = state.colorBlendEquation.dstColor,
            .colorBlendOp = state.colorBlendEquation.colorOperation,
            .srcAlphaBlendFactor = state.colorBlendEquation.srcAlpha,
            .dstAlphaBlendFactor = state.colorBlendEquation.dstAlpha,
            .alphaBlendOp = state.colorBlendEquation.alphaOperation,
        };
        const equations = [_]vk.VkColorBlendEquationEXT{blendEquation} ** 8;
        vkFn.vkCmdSetColorBlendEquationEXT.?(cmd, 0, 8, &equations);

        const blendConsts = [_]f32{ state.blendConstants.red, state.blendConstants.green, state.blendConstants.blue, state.blendConstants.alpha };
        vkFn.vkCmdSetBlendConstants.?(cmd, &blendConsts);

        const colWriteMask = state.colorWriteMask;
        const colWriteMasks = [_]vk.VkColorComponentFlags{colWriteMask} ** 8;
        vkFn.vkCmdSetColorWriteMaskEXT.?(cmd, 0, 8, &colWriteMasks);

        vkFn.vkCmdSetAlphaToOneEnableEXT.?(cmd, state.alphaToOne);
        vkFn.vkCmdSetAlphaToCoverageEnableEXT.?(cmd, state.alphaToCoverage);

        vkFn.vkCmdSetLogicOpEnableEXT.?(cmd, state.logicOp);
        vkFn.vkCmdSetLogicOpEXT.?(cmd, state.logicOpType);

        // Advanced / Debug
        vkFn.vkCmdSetLineWidth.?(cmd, state.lineWidth);
        vkFn.vkCmdSetConservativeRasterizationModeEXT.?(cmd, state.conservativeRasterMode);

        const combinerOps = [_]vk.VkFragmentShadingRateCombinerOpKHR{ state.fragShadingRate.operation, state.fragShadingRate.operation };
        vkFn.vkCmdSetFragmentShadingRateKHR.?(cmd, &.{ .width = state.fragShadingRate.width, .height = state.fragShadingRate.height }, &combinerOps);
    }

    pub fn createSubmitInfo(self: *const Command) vk.VkCommandBufferSubmitInfo {
        return vk.VkCommandBufferSubmitInfo{ .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO, .commandBuffer = self.handle };
    }
};

fn createSubresourceLayers(mask: u32, mipLevel: u32, arrayLayer: u32, layerCount: u32) vk.VkImageSubresourceLayers {
    return vk.VkImageSubresourceLayers{ .aspectMask = mask, .mipLevel = mipLevel, .baseArrayLayer = arrayLayer, .layerCount = layerCount };
}

fn calculateBlitOffsets(srcImgExtent: vk.VkExtent3D, dstImgExtent: vk.VkExtent3D, stretch: bool) struct { srcOffsets: [2]vk.VkOffset3D, dstOffsets: [2]vk.VkOffset3D } {
    var srcOffsets: [2]vk.VkOffset3D = undefined;
    var dstOffsets: [2]vk.VkOffset3D = undefined;

    if (stretch == true) {
        // Stretch: Source is full image, Dest is full window
        srcOffsets[0] = .{ .x = 0, .y = 0, .z = 0 };
        srcOffsets[1] = .{ .x = @intCast(srcImgExtent.width), .y = @intCast(srcImgExtent.height), .z = 1 };
        dstOffsets[0] = .{ .x = 0, .y = 0, .z = 0 };
        dstOffsets[1] = .{ .x = @intCast(dstImgExtent.width), .y = @intCast(dstImgExtent.height), .z = 1 };
    } else {
        // No Stretch (Center / Crop)
        const srcW: i32 = @intCast(srcImgExtent.width);
        const srcH: i32 = @intCast(srcImgExtent.height);
        const winW: i32 = @intCast(dstImgExtent.width);
        const winH: i32 = @intCast(dstImgExtent.height);
        // Determine the size of the region to copy (smaller of the two dimensions)
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
    return .{ .srcOffsets = srcOffsets, .dstOffsets = dstOffsets };
}
