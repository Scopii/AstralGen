const LinkedMap = @import("../../../structures/LinkedMap.zig").LinkedMap;
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
    flightId: u8 = 0,
    frame: u64 = 0,
    renderState: ?RenderState = null,

    queryPool: ?vk.VkQueryPool = null,
    queryCounter: u8 = 0,
    querys: LinkedMap(Query, rc.GPU_QUERYS, u8, rc.GPU_QUERYS * 2, 0) = .{},

    pub fn init(cmdPool: vk.VkCommandPool, level: vk.VkCommandBufferLevel, gpi: vk.VkDevice) !Cmd {
        const allocInf = vk.VkCommandBufferAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = cmdPool,
            .level = level,
            .commandBufferCount = 1,
        };
        var cmd: vk.VkCommandBuffer = undefined;
        try vhF.check(vk.vkAllocateCommandBuffers(gpi, &allocInf, &cmd), "Could not create Cmd");

        return .{
            .handle = cmd,
            .queryPool = null,
        };
    }

    pub fn deinit(self: *const Cmd, gpi: vk.VkDevice) void {
        if (self.queryPool) |qPool| vk.vkDestroyQueryPool(gpi, qPool, null);
    }

    pub fn beginLabel(self: *const Cmd, label: [:0]const u8, color: ?[4]f32) void {
        if (rc.VALIDATION == true) {
            const labelInf = vk.VkDebugUtilsLabelEXT{
                .sType = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT,
                .pLabelName = label.ptr,
                .color = if (color) |col| col else [4]f32{ 1.0, 1.0, 1.0, 1.0 },
            };
            vkFn.vkCmdBeginDebugUtilsLabelEXT.?(self.handle, &labelInf);
        }
    }

    pub fn endLabel(self: *const Cmd) void {
        if (rc.VALIDATION == true) vkFn.vkCmdEndDebugUtilsLabelEXT.?(self.handle);
    }

    pub fn enableQuerys(self: *Cmd, gpi: vk.VkDevice) !void {
        if (self.queryPool == null) {
            const poolInfo = vk.VkQueryPoolCreateInfo{
                .sType = vk.VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
                .queryType = vk.VK_QUERY_TYPE_TIMESTAMP,
                .queryCount = rc.GPU_QUERYS * 2,
            };
            var tempQueryPool: vk.VkQueryPool = undefined;
            try vhF.check(vk.vkCreateQueryPool(gpi, &poolInfo, null, &tempQueryPool), "Could not init Cmd QueryPool");
            self.queryPool = tempQueryPool;
        }
    }

    pub fn disableQuerys(self: *Cmd, gpi: vk.VkDevice) void {
        if (self.queryPool) |qPool| {
            vk.vkDestroyQueryPool(gpi, qPool, null);
            self.queryPool = null;
        }
    }

    pub fn begin(self: *Cmd, flightId: u8, frame: u64) !void {
        const beginInf = vk.VkCommandBufferBeginInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, //vk.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT
            .pInheritanceInfo = null,
        };
        self.flightId = flightId;
        self.frame = frame;
        self.renderState = null;

        try vhF.check(vk.vkResetCommandBuffer(self.handle, 0), "could not reset Cmd");
        try vhF.check(vk.vkBeginCommandBuffer(self.handle, &beginInf), "could not Begin Cmd");
    }

    pub fn end(self: *const Cmd) !void {
        try vhF.check(vk.vkEndCommandBuffer(self.handle), "Could not End Cmd Buffer");
    }

    fn writeTimestamp(self: *const Cmd, pool: vk.VkQueryPool, stage: vk.VkPipelineStageFlagBits2, queryIndex: u32) void {
        vk.vkCmdWriteTimestamp2(self.handle, stage, pool, queryIndex);
    }

    pub fn startQuery(self: *Cmd, pipeStage: vhE.PipeStage, queryId: u8, name: []const u8) void {
        if (self.queryPool) |qPool| {
            if (self.querys.isKeyUsed(queryId) == true) {
                std.debug.print("Cmd Warning: Query ID {} in use by {s}\n!", .{ queryId, self.querys.getPtrByKey(queryId).name });
                return;
            }
            const idx = self.queryCounter;
            if (idx >= rc.GPU_QUERYS) {
                std.debug.print("GPU Querys full\n", .{});
                return;
            }

            self.writeTimestamp(qPool, @intFromEnum(pipeStage), idx);
            self.querys.upsert(queryId, .{ .name = name, .startIndex = idx });
            self.queryCounter += 1;
        }
    }

    pub fn endQuery(self: *Cmd, pipeStage: vhE.PipeStage, queryId: u8) void {
        if (self.queryPool) |qPool| {
            if (self.querys.isKeyUsed(queryId) == false) {
                std.debug.print("Cmd Error: QueryId {} not registered", .{queryId});
                return;
            }

            const idx = self.queryCounter;
            if (idx >= rc.GPU_QUERYS) {
                std.debug.print("GPU Querys full\n", .{});
                return;
            }

            self.writeTimestamp(qPool, @intFromEnum(pipeStage), idx);
            const query = self.querys.getPtrByKey(queryId);
            query.endIndex = idx;
            self.queryCounter += 1;
        }
    }

    pub fn printQueryResults(self: *Cmd, gpi: vk.VkDevice, timestampPeriod: f32) !void {
        if (self.queryPool) |qPool| {
            const count = self.queryCounter;
            if (count == 0 or count > rc.GPU_QUERYS) {
                std.debug.print("No Querys in Cmd to print\n", .{});
                return;
            }

            var results: [rc.GPU_QUERYS * 2]u64 = undefined;
            const flags = vk.VK_QUERY_RESULT_64_BIT | vk.VK_QUERY_RESULT_WAIT_BIT;
            try vhF.check(vk.vkGetQueryPoolResults(gpi, qPool, 0, count, @sizeOf(u64) * 128, &results, @sizeOf(u64), flags), "Failed getting Cmd Queries");

            const frameStartIndex = self.querys.getByIndex(0).startIndex;
            const frameStart = results[frameStartIndex];
            var frameEnd: u64 = 0;

            for (self.querys.getItems()) |query| {
                const endTime = results[query.endIndex];
                if (endTime > frameEnd) frameEnd = endTime;
            }

            const ticks = frameEnd - frameStart;
            const gpuFrameMs = (@as(f64, @floatFromInt(ticks)) * timestampPeriod) / 1_000_000.0;
            std.debug.print("GPU Frame {} (FlightID {}) ({}/{} Queries)\n", .{ self.frame, self.flightId, self.querys.getLength(), rc.GPU_QUERYS });
            std.debug.print("{d:.3} ms ({d:.1} FPS) ({} GPU Ticks):\n", .{ gpuFrameMs, 1000.0 / gpuFrameMs, ticks });

            var untrackedMs: f64 = gpuFrameMs;

            for (self.querys.getItems()) |query| {
                const diff = results[query.endIndex] - results[query.startIndex];
                const gpuQueryMs = (@as(f64, @floatFromInt(diff)) * timestampPeriod) / 1_000_000.0;
                untrackedMs -= gpuQueryMs;
                std.debug.print(" - {d:.3} ms ({d:5.2} %) {s}\n", .{ gpuQueryMs, (gpuQueryMs / gpuFrameMs) * 100, query.name });
            }
            std.debug.print("Untracked {d:.3} ms ({d:5.2} %)\n", .{ untrackedMs + 0.00001, untrackedMs * 100 + 0.00001 }); // + 0.00001 to avoid negative through precision loss
        }
    }

    pub fn resetQuerys(self: *Cmd) void {
        if (self.queryPool) |qPool| {
            vk.vkCmdResetQueryPool(self.handle, qPool, 0, rc.GPU_QUERYS * 2);
            self.queryCounter = 0;
            self.querys.clear();
        }
    }

    pub fn bakeBarriers(self: *const Cmd, imgBarriers: []const vk.VkImageMemoryBarrier2, bufBarriers: []const vk.VkBufferMemoryBarrier2) void {
        const depInf = vk.VkDependencyInfo{
            //.dependencyFlags =
            .sType = vk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .imageMemoryBarrierCount = @intCast(imgBarriers.len),
            .pImageMemoryBarriers = imgBarriers.ptr,
            .bufferMemoryBarrierCount = @intCast(bufBarriers.len),
            .pBufferMemoryBarriers = bufBarriers.ptr,
            //.memoryBarrierCount =
            //.pMemoryBarriers =
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

    pub fn updateRenderState(self: *Cmd, new: RenderState) void {
        const cmd = self.handle;

        var old: RenderState = undefined;
        var force = false;

        if (self.renderState) |renderState| old = renderState else force = true;

        // Rasterization & Geometry
        if (force or old.polygonMode != new.polygonMode) vkFn.vkCmdSetPolygonModeEXT.?(cmd, new.polygonMode);
        if (force or old.cullMode != new.cullMode) vk.vkCmdSetCullMode(cmd, new.cullMode);
        if (force or old.frontFace != new.frontFace) vk.vkCmdSetFrontFace(cmd, new.frontFace);
        if (force or old.topology != new.topology) vk.vkCmdSetPrimitiveTopology(cmd, new.topology);

        if (force or old.primitiveRestart != new.primitiveRestart) vk.vkCmdSetPrimitiveRestartEnable(cmd, new.primitiveRestart);
        if (force or old.rasterDiscard != new.rasterDiscard) vk.vkCmdSetRasterizerDiscardEnable(cmd, new.rasterDiscard);
        if (force or old.rasterSamples != new.rasterSamples) vkFn.vkCmdSetRasterizationSamplesEXT.?(cmd, new.rasterSamples);

        const sampleMask: u32 = new.sample.sampleMask;
        if (force or !std.meta.eql(old.sample, new.sample)) vkFn.vkCmdSetSampleMaskEXT.?(cmd, new.sample.sampling, &sampleMask);

        // Depth & Stencil
        if (force or old.depthBoundsTest != new.depthBoundsTest) vk.vkCmdSetDepthBoundsTestEnable(cmd, new.depthBoundsTest);
        if (force or old.depthBias != new.depthBias) vk.vkCmdSetDepthBiasEnable(cmd, new.depthBias);
        if (force or old.depthClamp != new.depthClamp) vkFn.vkCmdSetDepthClampEnableEXT.?(cmd, new.depthClamp);

        if (force or old.depthTest != new.depthTest) vk.vkCmdSetDepthTestEnable(cmd, new.depthTest);
        if (force or old.depthWrite != new.depthWrite) vk.vkCmdSetDepthWriteEnable(cmd, new.depthWrite);
        if (force or old.depthCompare != new.depthCompare) vk.vkCmdSetDepthCompareOp(cmd, new.depthCompare);
        if (force or !std.meta.eql(old.depthValues, new.depthValues)) vk.vkCmdSetDepthBias(cmd, new.depthValues.constant, new.depthValues.clamp, new.depthValues.slope);

        if (force or old.stencilTest != new.stencilTest) vk.vkCmdSetStencilTestEnable(cmd, new.stencilTest);
        if (force or !std.meta.eql(old.stencilOp, new.stencilOp)) vk.vkCmdSetStencilOp(cmd, new.stencilOp[0], new.stencilOp[1], new.stencilOp[2], new.stencilOp[3], new.stencilOp[4]);
        if (force or !std.meta.eql(old.stencilCompare, new.stencilCompare)) vk.vkCmdSetStencilCompareMask(cmd, new.stencilCompare.faceMask, new.stencilCompare.mask);
        if (force or !std.meta.eql(old.stencilWrite, new.stencilWrite)) vk.vkCmdSetStencilWriteMask(cmd, new.stencilWrite.faceMask, new.stencilWrite.mask);
        if (force or !std.meta.eql(old.stencilReference, new.stencilReference)) vk.vkCmdSetStencilReference(cmd, new.stencilReference.faceMask, new.stencilReference.mask);

        // Color & Blending
        const blendEnable = new.colorBlend;
        const colorBlendAttachments = [_]vk.VkBool32{blendEnable} ** 8;
        if (force or old.colorBlend != new.colorBlend) vkFn.vkCmdSetColorBlendEnableEXT.?(cmd, 0, 8, &colorBlendAttachments);

        const oldBlendEquation = vk.VkColorBlendEquationEXT{
            .srcColorBlendFactor = old.colorBlendEquation.srcColor,
            .dstColorBlendFactor = old.colorBlendEquation.dstColor,
            .colorBlendOp = old.colorBlendEquation.colorOperation,
            .srcAlphaBlendFactor = old.colorBlendEquation.srcAlpha,
            .dstAlphaBlendFactor = old.colorBlendEquation.dstAlpha,
            .alphaBlendOp = old.colorBlendEquation.alphaOperation,
        };

        const blendEquation = vk.VkColorBlendEquationEXT{
            .srcColorBlendFactor = new.colorBlendEquation.srcColor,
            .dstColorBlendFactor = new.colorBlendEquation.dstColor,
            .colorBlendOp = new.colorBlendEquation.colorOperation,
            .srcAlphaBlendFactor = new.colorBlendEquation.srcAlpha,
            .dstAlphaBlendFactor = new.colorBlendEquation.dstAlpha,
            .alphaBlendOp = new.colorBlendEquation.alphaOperation,
        };
        const equations = [_]vk.VkColorBlendEquationEXT{blendEquation} ** 8;
        if (force or !std.meta.eql(oldBlendEquation, blendEquation)) vkFn.vkCmdSetColorBlendEquationEXT.?(cmd, 0, 8, &equations);

        const oldBlendConsts = [_]f32{ old.blendConstants.red, old.blendConstants.green, old.blendConstants.blue, old.blendConstants.alpha };
        const blendConsts = [_]f32{ new.blendConstants.red, new.blendConstants.green, new.blendConstants.blue, new.blendConstants.alpha };
        if (force or !std.meta.eql(oldBlendConsts, blendConsts)) vk.vkCmdSetBlendConstants(cmd, &blendConsts);

        const colWriteMasks = [_]vk.VkColorComponentFlags{new.colorWriteMask} ** 8;
        if (force or old.colorWriteMask != new.colorWriteMask) vkFn.vkCmdSetColorWriteMaskEXT.?(cmd, 0, 8, &colWriteMasks);

        if (force or old.alphaToOne != new.alphaToOne) vkFn.vkCmdSetAlphaToOneEnableEXT.?(cmd, new.alphaToOne);
        if (force or old.alphaToCoverage != new.alphaToCoverage) vkFn.vkCmdSetAlphaToCoverageEnableEXT.?(cmd, new.alphaToCoverage);

        if (force or old.logicOp != new.logicOp) vkFn.vkCmdSetLogicOpEnableEXT.?(cmd, new.logicOp);
        if (force or old.logicOpType != new.logicOpType) vkFn.vkCmdSetLogicOpEXT.?(cmd, new.logicOpType);

        // Advanced / Debug
        if (force or old.lineWidth != new.lineWidth) vk.vkCmdSetLineWidth(cmd, new.lineWidth);
        if (force or old.conservativeRasterMode != new.conservativeRasterMode) vkFn.vkCmdSetConservativeRasterizationModeEXT.?(cmd, new.conservativeRasterMode);

        const combinerOps = [_]vk.VkFragmentShadingRateCombinerOpKHR{ new.fragShadingRate.operation, new.fragShadingRate.operation };
        const extent = vk.VkExtent2D{ .width = new.fragShadingRate.width, .height = new.fragShadingRate.height };
        if (force or !std.meta.eql(old.fragShadingRate, new.fragShadingRate)) vkFn.vkCmdSetFragmentShadingRateKHR.?(cmd, &extent, &combinerOps);

        self.renderState = new;
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
