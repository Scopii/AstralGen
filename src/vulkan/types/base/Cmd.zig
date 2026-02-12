const CreateMapArray = @import("../../../structures/MapArray.zig").CreateMapArray;
const Transfer = @import("../../sys/ResourceMan.zig").Transfer;
const RenderState = @import("RenderState.zig").RenderState;
const rc = @import("../../../configs/renderConfig.zig");
const vk = @import("../../../modules/vk.zig").c;
const vkFn = @import("../../../modules/vk.zig");
const vhF = @import("../../help/Functions.zig");
const vhE = @import("../../help/Enums.zig");
const Shader = @import("Shader.zig").Shader;
const std = @import("std");

pub const Query = struct {
    name: []const u8,
    startIndex: u8 = 0,
    endIndex: u8 = 0,
};

pub const Cmd = struct {
    handle: vk.VkCommandBuffer,
    queryPool: vk.VkQueryPool,
    queryCounter: u8 = 0,
    querys: CreateMapArray(Query, rc.GPU_QUERYS, u8, rc.GPU_QUERYS * 2, 0) = .{},
    flightId: u8 = 0,
    frame: u64 = 0,

    pub fn init(cmdPool: vk.VkCommandPool, level: vk.VkCommandBufferLevel, gpi: vk.VkDevice) !Cmd {
        const allocInf = vk.VkCommandBufferAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = cmdPool,
            .level = level,
            .commandBufferCount = 1,
        };
        var cmd: vk.VkCommandBuffer = undefined;
        try vhF.check(vk.vkAllocateCommandBuffers(gpi, &allocInf, &cmd), "Could not create Cmd Buffer");

        const poolInfo = vk.VkQueryPoolCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
            .queryType = vk.VK_QUERY_TYPE_TIMESTAMP,
            .queryCount = rc.GPU_QUERYS * 2,
        };
        var queryPool: vk.VkQueryPool = undefined;
        try vhF.check(vk.vkCreateQueryPool(gpi, &poolInfo, null, &queryPool), "Could not init QueryPool");

        return .{
            .handle = cmd,
            .queryPool = queryPool,
        };
    }

    pub fn deinit(self: *const Cmd, gpi: vk.VkDevice) void {
        vk.vkDestroyQueryPool(gpi, self.queryPool, null);
    }

    pub fn begin(self: *Cmd, flightId: u8, frame: u64) !void {
        const beginInf = vk.VkCommandBufferBeginInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, //vk.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT
            .pInheritanceInfo = null,
        };
        self.flightId = flightId;
        self.frame = frame;
        try vhF.check(vk.vkBeginCommandBuffer(self.handle, &beginInf), "could not Begin CmdBuffer");
    }

    pub fn end(self: *const Cmd) !void {
        try vhF.check(vk.vkEndCommandBuffer(self.handle), "Could not End CmdBuffer");
    }

    fn writeTimestamp(self: *const Cmd, pool: vk.VkQueryPool, stage: vk.VkPipelineStageFlagBits2, queryIndex: u32) void {
        vk.vkCmdWriteTimestamp2(self.handle, stage, pool, queryIndex);
    }

    pub fn startQuery(self: *Cmd, pipeStage: vhE.PipeStage, queryId: u8, name: []const u8) void {
        if (self.querys.isKeyUsed(queryId) == true) {
            std.debug.print("Warning: Query ID {} in use by {s}\n!", .{ queryId, self.querys.getPtr(queryId).name });
            return;
        }
        const idx = self.queryCounter;
        if (idx >= rc.GPU_QUERYS) return; // Safety check

        self.writeTimestamp(self.queryPool, @intFromEnum(pipeStage), idx);
        self.querys.set(queryId, .{ .name = name, .startIndex = idx });
        self.queryCounter += 1;
    }

    pub fn endQuery(self: *Cmd, pipeStage: vhE.PipeStage, queryId: u8) void {
        if (self.querys.isKeyUsed(queryId) == false) {
            std.debug.print("Error: QueryId {} not registered", .{queryId});
            return;
        }

        const idx = self.queryCounter;
        if (idx >= rc.GPU_QUERYS) return; // Safety check

        self.writeTimestamp(self.queryPool, @intFromEnum(pipeStage), idx);
        const query = self.querys.getPtr(queryId);
        query.endIndex = idx;
        self.queryCounter += 1;
    }

    pub fn printQueryResults(self: *Cmd, gpi: vk.VkDevice, timestampPeriod: f32) !void {
        const count = self.queryCounter;
        if (count == 0 or count > rc.GPU_QUERYS) {
            std.debug.print("No Querys in Cmd to print\n", .{});
            return;
        }

        var results: [rc.GPU_QUERYS * 2]u64 = undefined;
        const flags = vk.VK_QUERY_RESULT_64_BIT | vk.VK_QUERY_RESULT_WAIT_BIT;
        try vhF.check(vk.vkGetQueryPoolResults(gpi, self.queryPool, 0, count, @sizeOf(u64) * 128, &results, @sizeOf(u64), flags), "Failed getting Queries");

        const frameStartIndex = self.querys.getAtIndex(0).startIndex;
        const frameStart = results[frameStartIndex];
        var frameEnd: u64 = 0;

        for (self.querys.getElements()) |query| {
            const endTime = results[query.endIndex];
            if (endTime > frameEnd) frameEnd = endTime;
        }

        const ticks = frameEnd - frameStart;
        const gpuFrameMs = (@as(f64, @floatFromInt(ticks)) * timestampPeriod) / 1_000_000.0;
        std.debug.print("GPU Frame {} (FlightID {}) ({}/{} Queries)\n", .{ self.frame, self.flightId, self.querys.getCount(), rc.GPU_QUERYS });
        std.debug.print("{d:.3} ms ({d:.1} FPS) ({} GPU Ticks):\n", .{ gpuFrameMs, 1000.0 / gpuFrameMs, ticks });

        var untrackedMs: f64 = gpuFrameMs;

        for (self.querys.getElements()) |query| {
            const diff = results[query.endIndex] - results[query.startIndex];
            const gpuQueryMs = (@as(f64, @floatFromInt(diff)) * timestampPeriod) / 1_000_000.0;
            untrackedMs -= gpuQueryMs;
            std.debug.print(" - {d:.3} ms ({d:5.2} %) {s}\n", .{ gpuQueryMs, (gpuQueryMs / gpuFrameMs) * 100, query.name });
        }
        std.debug.print("Untracked {d:.3} ms ({d:5.2} %)\n", .{ untrackedMs + 0.00001, untrackedMs * 100 + 0.00001 }); // + 0.00001 to avoid negative through precision loss
    }

    pub fn resetQuerys(self: *Cmd) void {
        vk.vkCmdResetQueryPool(self.handle, self.queryPool, 0, rc.GPU_QUERYS * 2);
        self.queryCounter = 0;
        self.querys.clear();
    }

    pub fn bakeBarriers(self: *const Cmd, imgBarriers: []const vk.VkImageMemoryBarrier2, bufBarriers: []const vk.VkBufferMemoryBarrier2) void {
        const depInf = vk.VkDependencyInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .imageMemoryBarrierCount = @intCast(imgBarriers.len),
            .pImageMemoryBarriers = imgBarriers.ptr,
            .bufferMemoryBarrierCount = @intCast(bufBarriers.len),
            .pBufferMemoryBarriers = bufBarriers.ptr,
        };
        vk.vkCmdPipelineBarrier2(self.handle, &depInf);
    }

    pub fn setPushConstants(self: *const Cmd, layout: vk.VkPipelineLayout, stageFlags: vk.VkShaderStageFlags, offset: u32, size: u32, pcs: ?*const anyopaque) void {
        vk.vkCmdPushConstants(self.handle, layout, stageFlags, offset, size, pcs);
    }

    pub fn setPushData(self: *const Cmd, dataPtr: ?*const anyopaque, size: u32, offset: u32) void {
        const pushDataInf = vk.VkPushDataInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_PUSH_DATA_INFO_EXT,
            .offset = offset,
            .data = .{ .address = dataPtr, .size = size },
        };
        vkFn.vkCmdPushDataEXT.?(self.handle, &pushDataInf);
    }

    pub fn setEmptyVertexInput(self: *const Cmd) void {
        vkFn.vkCmdSetVertexInputEXT.?(self.handle, 0, null, 0, null);
    }

    pub fn draw(self: *const Cmd, vertexCount: u32, instanceCount: u32, firstVertex: u32, firstInstance: u32) void {
        vk.vkCmdDraw(self.handle, vertexCount, instanceCount, firstVertex, firstInstance);
    }

    pub fn drawIndirect(self: *const Cmd, buffer: vk.VkBuffer, offset: u64, drawCount: u32, stride: u32) void {
        vk.vkCmdDrawIndirect(self.handle, buffer, offset, drawCount, stride);
    }

    pub fn drawMeshTasks(self: *const Cmd, workgroupsX: u32, workgroupsY: u32, workgroupsZ: u32) void {
        vkFn.vkCmdDrawMeshTasksEXT.?(self.handle, workgroupsX, workgroupsY, workgroupsZ);
    }

    pub fn drawMeshTasksIndirect(self: *const Cmd, buffer: vk.VkBuffer, offset: u64, drawCount: u32, stride: u32) void {
        vkFn.vkCmdDrawMeshTasksIndirectEXT.?(self.handle, buffer, offset, drawCount, stride);
    }

    pub fn endRendering(self: *const Cmd) void {
        vk.vkCmdEndRendering(self.handle);
    }

    pub fn bindDescriptorHeap(self: *const Cmd, heapAddress: u64, heapSize: u64, reservedSize: u64) void {
        const bindInf = vk.VkBindHeapInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_BIND_HEAP_INFO_EXT,
            .heapRange = .{ .address = heapAddress, .size = heapSize },
            .reservedRangeOffset = 0,
            .reservedRangeSize = reservedSize,
        };
        vkFn.vkCmdBindResourceHeapEXT.?(self.handle, &bindInf);
    }

    pub fn copyImageToImage(self: *const Cmd, srcImg: vk.VkImage, srcExtent: vk.VkExtent3D, dstImg: vk.VkImage, dstExtent: vk.VkExtent3D, stretch: bool) void {
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
        self: *const Cmd,
        width: u32,
        height: u32,
        colorInfs: []const vk.VkRenderingAttachmentInfo,
        depthInf: ?*const vk.VkRenderingAttachmentInfo,
        stencilInf: ?*const vk.VkRenderingAttachmentInfo,
    ) void {
        const viewport = vk.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        vk.vkCmdSetViewportWithCount(self.handle, 1, &viewport);

        const scissor = vk.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = width, .height = height },
        };

        vk.vkCmdSetScissorWithCount(self.handle, 1, &scissor);

        const renderInf = vk.VkRenderingInfo{
            .sType = vk.VK_STRUCTURE_TYPE_RENDERING_INFO,
            .flags = 0,
            .renderArea = scissor,
            .layerCount = 1,
            .viewMask = 0,
            .colorAttachmentCount = @intCast(colorInfs.len),
            .pColorAttachments = colorInfs.ptr,
            .pDepthAttachment = if (depthInf != null) depthInf.? else null,
            .pStencilAttachment = if (stencilInf != null) stencilInf.? else null,
        };

        vk.vkCmdBeginRendering(self.handle, &renderInf);
    }

    pub fn bindShaders(self: *const Cmd, shaders: []const Shader) void {
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
            const activeStageBit = vhF.getShaderBit(shader.stage);

            for (0..8) |i| {
                if (allStages[i] == activeStageBit) {
                    handles[i] = shader.handle;
                    break;
                }
            }
        }
        vkFn.vkCmdBindShadersEXT.?(self.handle, 8, &allStages, &handles);
    }

    pub fn dispatch(self: *const Cmd, groupCountX: u32, groupCountY: u32, groupCountZ: u32) void {
        vk.vkCmdDispatch(self.handle, groupCountX, groupCountY, groupCountZ);
    }

    pub fn fillBuffer(self: *const Cmd, buffer: vk.VkBuffer, offset: u64, size: u64, data: u32) void {
        vk.vkCmdFillBuffer(self.handle, buffer, offset, size, data);
    }

    pub fn copyBuffer(self: *const Cmd, srcBuffer: vk.VkBuffer, transfer: *const Transfer, dstBuffer: vk.VkBuffer) void {
        const copy = vk.VkBufferCopy{ .srcOffset = transfer.srcOffset, .dstOffset = 0, .size = transfer.size };
        vk.vkCmdCopyBuffer(self.handle, srcBuffer, dstBuffer, 1, &copy);
    }

    pub fn setGraphicsState(self: *const Cmd, state: RenderState) void {
        const cmd = self.handle;

        // Rasterization & Geometry
        vkFn.vkCmdSetPolygonModeEXT.?(cmd, state.polygonMode);
        vk.vkCmdSetCullMode(cmd, state.cullMode);
        vk.vkCmdSetFrontFace(cmd, state.frontFace);
        vk.vkCmdSetPrimitiveTopology(cmd, state.topology);

        vk.vkCmdSetPrimitiveRestartEnable(cmd, state.primitiveRestart);
        vk.vkCmdSetRasterizerDiscardEnable(cmd, state.rasterDiscard);
        vkFn.vkCmdSetRasterizationSamplesEXT.?(cmd, state.rasterSamples);

        const sampleMask: u32 = state.sample.sampleMask;
        vkFn.vkCmdSetSampleMaskEXT.?(cmd, state.sample.sampling, &sampleMask);

        // Depth & Stencil
        vk.vkCmdSetDepthBoundsTestEnable(cmd, state.depthBoundsTest);
        vk.vkCmdSetDepthBiasEnable(cmd, state.depthBias);
        vkFn.vkCmdSetDepthClampEnableEXT.?(cmd, state.depthClamp);

        vk.vkCmdSetDepthTestEnable(cmd, state.depthTest);
        vk.vkCmdSetDepthWriteEnable(cmd, state.depthWrite);
        vk.vkCmdSetDepthCompareOp(cmd, state.depthCompare);
        vk.vkCmdSetDepthBias(cmd, state.depthValues.constant, state.depthValues.clamp, state.depthValues.slope);

        vk.vkCmdSetStencilTestEnable(cmd, state.stencilTest);
        vk.vkCmdSetStencilOp(cmd, state.stencilOp[0], state.stencilOp[1], state.stencilOp[2], state.stencilOp[3], state.stencilOp[4]);
        vk.vkCmdSetStencilCompareMask(cmd, state.stencilCompare.faceMask, state.stencilCompare.mask);
        vk.vkCmdSetStencilWriteMask(cmd, state.stencilWrite.faceMask, state.stencilWrite.mask);
        vk.vkCmdSetStencilReference(cmd, state.stencilReference.faceMask, state.stencilReference.mask);

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
        vk.vkCmdSetBlendConstants(cmd, &blendConsts);

        const colWriteMask = state.colorWriteMask;
        const colWriteMasks = [_]vk.VkColorComponentFlags{colWriteMask} ** 8;
        vkFn.vkCmdSetColorWriteMaskEXT.?(cmd, 0, 8, &colWriteMasks);

        vkFn.vkCmdSetAlphaToOneEnableEXT.?(cmd, state.alphaToOne);
        vkFn.vkCmdSetAlphaToCoverageEnableEXT.?(cmd, state.alphaToCoverage);

        vkFn.vkCmdSetLogicOpEnableEXT.?(cmd, state.logicOp);
        vkFn.vkCmdSetLogicOpEXT.?(cmd, state.logicOpType);

        // Advanced / Debug
        vk.vkCmdSetLineWidth(cmd, state.lineWidth);
        vkFn.vkCmdSetConservativeRasterizationModeEXT.?(cmd, state.conservativeRasterMode);

        const combinerOps = [_]vk.VkFragmentShadingRateCombinerOpKHR{ state.fragShadingRate.operation, state.fragShadingRate.operation };
        vkFn.vkCmdSetFragmentShadingRateKHR.?(cmd, &.{ .width = state.fragShadingRate.width, .height = state.fragShadingRate.height }, &combinerOps);
    }

    pub fn createSubmitInfo(self: *const Cmd) vk.VkCommandBufferSubmitInfo {
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
