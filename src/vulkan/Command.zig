const vk = @import("../modules/vk.zig").c;
const vkFn = @import("../modules/vk.zig");
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const PendingTransfer = @import("resources/ResourceManager.zig").PendingTransfer;
const vh = @import("Helpers.zig");

pub const Command = struct {
    handle: vk.VkCommandBuffer,

    pub fn init(cmd: vk.VkCommandBuffer) !Command {
        return .{ .handle = cmd };
    }

    pub fn endRecording(self: *const Command) !void {
        try vh.check(vk.vkEndCommandBuffer(self.handle), "Could not End Cmd Buffer");
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

    pub fn drawMeshTasks(self: *const Command, workgroupsX: u32, workgroupsY: u32, workgroupsZ: u32) void {
        vkFn.vkCmdDrawMeshTasksEXT.?(self.handle, workgroupsX, workgroupsY, workgroupsZ);
    }

    pub fn drawMeshTasksIndirect(self: *const Command, buffer: vk.VkBuffer, offset: u64, drawCount: u32, stride: u32) void {
        vkFn.vkCmdDrawMeshTasksIndirectEXT.?(self.handle, buffer, offset, drawCount, stride);
    }

    pub fn endRendering(self: *const Command) void {
        vk.vkCmdEndRendering(self.handle);
    }

    pub fn getHandle(self: *const Command) vk.VkCommandBuffer {
        return self.handle;
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

    pub fn bindShaders(self: *const Command, shaderObjects: []const ShaderObject) void {
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

        for (shaderObjects) |shader| {
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

    pub fn copyBuffer(self: *const Command, srcBuffer: vk.VkBuffer, transfer: *const PendingTransfer, dstBuffer: vk.VkBuffer) void {
        const copy = vk.VkBufferCopy{ .srcOffset = transfer.srcOffset, .dstOffset = 0, .size = transfer.size };
        vk.vkCmdCopyBuffer(self.handle, srcBuffer, dstBuffer, 1, &copy);
    }

    pub fn setGraphicsState(self: *const Command) void {
        const cmd = self.handle;

        // Rasterization & Geometry
        vkFn.vkCmdSetPolygonModeEXT.?(cmd, vk.VK_POLYGON_MODE_FILL);
        vkFn.vkCmdSetCullMode.?(cmd, vk.VK_CULL_MODE_FRONT_BIT);
        vkFn.vkCmdSetFrontFace.?(cmd, vk.VK_FRONT_FACE_CLOCKWISE);
        vkFn.vkCmdSetPrimitiveTopology.?(cmd, vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
        vkFn.vkCmdSetPrimitiveRestartEnable.?(cmd, vk.VK_FALSE);
        vkFn.vkCmdSetRasterizerDiscardEnable.?(cmd, vk.VK_FALSE);
        vkFn.vkCmdSetRasterizationSamplesEXT.?(cmd, vk.VK_SAMPLE_COUNT_1_BIT);

        const sampleMask: u32 = 0xFFFFFFFF;
        vkFn.vkCmdSetSampleMaskEXT.?(cmd, vk.VK_SAMPLE_COUNT_1_BIT, &sampleMask);

        // Depth & Stencil
        vkFn.vkCmdSetDepthTestEnable.?(cmd, vk.VK_FALSE);
        vkFn.vkCmdSetDepthWriteEnable.?(cmd, vk.VK_FALSE);
        vkFn.vkCmdSetDepthBoundsTestEnable.?(cmd, vk.VK_FALSE);
        vkFn.vkCmdSetDepthBiasEnable.?(cmd, vk.VK_FALSE);
        vkFn.vkCmdSetDepthBias.?(cmd, 0.0, 0.0, 0.0);
        vkFn.vkCmdSetDepthClampEnableEXT.?(cmd, vk.VK_FALSE);
        vkFn.vkCmdSetStencilTestEnable.?(cmd, vk.VK_FALSE);

        // Color & Blending
        const colorBlendEnable = vk.VK_TRUE;
        const colorBlendAttachments = [_]vk.VkBool32{colorBlendEnable};
        vkFn.vkCmdSetColorBlendEnableEXT.?(cmd, 0, 1, &colorBlendAttachments);

        const blendEquation = vk.VkColorBlendEquationEXT{
            .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
            .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .colorBlendOp = vk.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp = vk.VK_BLEND_OP_ADD,
        };
        const equations = [_]vk.VkColorBlendEquationEXT{blendEquation};
        vkFn.vkCmdSetColorBlendEquationEXT.?(cmd, 0, 1, &equations);

        const colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT;
        const colorWriteMasks = [_]vk.VkColorComponentFlags{colorWriteMask};
        vkFn.vkCmdSetColorWriteMaskEXT.?(cmd, 0, 1, &colorWriteMasks);

        const blendConsts = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
        vkFn.vkCmdSetBlendConstants.?(cmd, &blendConsts);

        vkFn.vkCmdSetLogicOpEnableEXT.?(cmd, vk.VK_FALSE);
        vkFn.vkCmdSetAlphaToOneEnableEXT.?(cmd, vk.VK_FALSE);
        vkFn.vkCmdSetAlphaToCoverageEnableEXT.?(cmd, vk.VK_FALSE);

        // Advanced / Debug / Voxel Optimization
        vkFn.vkCmdSetLineWidth.?(cmd, 1.0);
        vkFn.vkCmdSetConservativeRasterizationModeEXT.?(cmd, vk.VK_CONSERVATIVE_RASTERIZATION_MODE_DISABLED_EXT);

        // Default to 1x1 Shading Rate (No reduction)
        const combinerOps = [_]vk.VkFragmentShadingRateCombinerOpKHR{ vk.VK_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_KHR, vk.VK_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_KHR };
        vkFn.vkCmdSetFragmentShadingRateKHR.?(cmd, &.{ .width = 1, .height = 1 }, &combinerOps);
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
