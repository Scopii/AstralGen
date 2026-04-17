const FixedList = @import("../../../.structures/FixedList.zig").FixedList;
const SimpleMap = @import("../../../.structures/SimpleMap.zig").SimpleMap;
const Transfer = @import("../../sys/ResourceUpdater.zig").Transfer;
const RenderState = @import("../pass/RenderState.zig").RenderState;
const rc = @import("../../../.configs/renderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const vkFn = @import("../../../.modules/vk.zig").vkFn;
const vhF = @import("../../help/Functions.zig");
const vhE = @import("../../help/Enums.zig");
const Shader = @import("Shader.zig").Shader;
const std = @import("std");

pub const QueryPair = struct {
    name: []const u8,
    typ: enum { Pass, Blit, Other },
    startIndex: u8 = 0,
    endIndex: u8 = 0,
};

pub const Cmd = struct {
    handle: vk.VkCommandBuffer,
    flightId: u8 = 0,
    frame: u64 = 0,
    renderState: ?RenderState = null,

    timeQueryPool: ?vk.VkQueryPool = null,
    timeQueryCounter: u8 = 0,
    timeQueries: SimpleMap(QueryPair, rc.GPU_TIME_QUERYS, u8, rc.GPU_TIME_QUERYS, 0) = .{},

    statQueryPool: ?vk.VkQueryPool = null,
    statQueries: FixedList(QueryPair, rc.GPU_STATS_QUERYS) = .{},
    activeStatQuery: ?QueryPair = null,

    stateChanges: u32 = 0,

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
        };
    }

    pub fn deinit(self: *const Cmd, gpi: vk.VkDevice) void {
        if (self.timeQueryPool) |qPool| vk.vkDestroyQueryPool(gpi, qPool, null);
        if (self.statQueryPool) |qPool| vk.vkDestroyQueryPool(gpi, qPool, null);
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

    pub fn enableTimeQuerys(self: *Cmd, gpi: vk.VkDevice) !void {
        if (self.timeQueryPool == null) {
            const poolInfo = vk.VkQueryPoolCreateInfo{
                .sType = vk.VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
                .queryType = vk.VK_QUERY_TYPE_TIMESTAMP,
                .queryCount = rc.GPU_TIME_QUERYS * 2,
            };
            var tempQueryPool: vk.VkQueryPool = undefined;
            try vhF.check(vk.vkCreateQueryPool(gpi, &poolInfo, null, &tempQueryPool), "Could not init Cmd QueryPool");
            self.timeQueryPool = tempQueryPool;
        }
    }

    pub fn disableTimeQuerys(self: *Cmd, gpi: vk.VkDevice) void {
        if (self.timeQueryPool) |qPool| {
            vk.vkDestroyQueryPool(gpi, qPool, null);
            self.timeQueryPool = null;
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
        self.stateChanges = 0;

        try vhF.check(vk.vkResetCommandBuffer(self.handle, 0), "could not reset Cmd");
        try vhF.check(vk.vkBeginCommandBuffer(self.handle, &beginInf), "could not Begin Cmd");
    }

    pub fn end(self: *const Cmd) !void {
        try vhF.check(vk.vkEndCommandBuffer(self.handle), "Could not End Cmd Buffer");
    }

    fn writeTimestamp(self: *const Cmd, pool: vk.VkQueryPool, stage: vk.VkPipelineStageFlagBits2, queryIndex: u32) void {
        vk.vkCmdWriteTimestamp2(self.handle, stage, pool, queryIndex);
    }

    pub fn startTimer(self: *Cmd, pipeStage: vhE.PipeStage, name: []const u8, typ: @FieldType(QueryPair, "typ")) ?u8 {
        if (self.timeQueryPool) |qPool| {
            const queryPairs: u8 = @intCast(self.timeQueries.getLength());
            if (queryPairs >= rc.GPU_TIME_QUERYS) {
                std.debug.print("GPU Querys Pairs full\n", .{});
                return null;
            }

            const index = self.timeQueryCounter;
            if (index >= rc.GPU_TIME_QUERYS * 2) {
                std.debug.print("GPU Querys full\n", .{});
                return null;
            }

            self.writeTimestamp(qPool, @intFromEnum(pipeStage), index);
            self.timeQueries.upsert(queryPairs, .{ .name = name, .typ = typ, .startIndex = index });
            self.timeQueryCounter += 1;
            return queryPairs;
        }
        return null;
    }

    pub fn endTimer(self: *Cmd, pipeStage: vhE.PipeStage, queryId: ?u8) void {
        const id = queryId orelse return;

        if (self.timeQueryPool) |qPool| {
            if (self.timeQueries.isKeyUsed(id) == false) {
                std.debug.print("Cmd Error: QueryId {} not registered", .{id});
                return;
            }

            const index = self.timeQueryCounter;
            if (index >= rc.GPU_TIME_QUERYS * 2) {
                std.debug.print("GPU Querys full\n", .{});
                return;
            }

            self.writeTimestamp(qPool, @intFromEnum(pipeStage), index);
            const query = self.timeQueries.getPtrByKey(id);
            query.endIndex = index;
            self.timeQueryCounter += 1;
        }
    }

    pub fn printTimeResults(self: *Cmd, gpi: vk.VkDevice, timestampPeriod: f32) !void {
        if (self.timeQueryPool) |qPool| {
            const count = self.timeQueryCounter;
            if (count == 0 or count > rc.GPU_TIME_QUERYS * 2) {
                std.debug.print("No Querys in Cmd to print\n", .{});
                return;
            }

            var results: [rc.GPU_TIME_QUERYS * 2]u64 = undefined;
            const flags = vk.VK_QUERY_RESULT_64_BIT; // | vk.VK_QUERY_RESULT_WAIT_BIT
            try vhF.check(vk.vkGetQueryPoolResults(gpi, qPool, 0, count, @sizeOf(u64) * 128, &results, @sizeOf(u64), flags), "Failed getting Cmd Queries");

            const frameStartIndex = self.timeQueries.getByIndex(0).startIndex;
            const frameStart = results[frameStartIndex];
            var frameEnd: u64 = 0;

            for (self.timeQueries.getItems()) |query| {
                const endTime = results[query.endIndex];
                if (endTime > frameEnd) frameEnd = endTime;
            }

            const ticks = frameEnd - frameStart;
            const gpuFrameMs = (@as(f64, @floatFromInt(ticks)) * timestampPeriod) / 1_000_000.0;
            std.debug.print("GPU Frame {} (FlightID {}) ({}/{} Queries)\n", .{ self.frame, self.flightId, self.timeQueries.getLength(), rc.GPU_TIME_QUERYS });
            std.debug.print("{d:.3} ms ({d:.1} FPS) ({} GPU Ticks):\n", .{ gpuFrameMs, 1000.0 / gpuFrameMs, ticks });

            var untrackedMs: f64 = gpuFrameMs;

            for (self.timeQueries.getItems()) |query| {
                const diff = results[query.endIndex] - results[query.startIndex];
                const gpuQueryMs = (@as(f64, @floatFromInt(diff)) * timestampPeriod) / 1_000_000.0;
                untrackedMs -= gpuQueryMs;
                std.debug.print(" - {d:.3} ms ({d:5.2} %) {}: {s}\n", .{ gpuQueryMs, (gpuQueryMs / gpuFrameMs) * 100, query.typ, query.name });
            }
            std.debug.print("Untracked {d:.3} ms ({d:5.2} %)\n", .{ untrackedMs + 0.00001, (untrackedMs / gpuFrameMs) * 100 + 0.00001 }); // + 0.00001 to avoid precision loss negative
        }
    }

    pub fn resetTimeQuerys(self: *Cmd) void {
        if (self.timeQueryPool) |qPool| {
            vk.vkCmdResetQueryPool(self.handle, qPool, 0, rc.GPU_TIME_QUERYS * 2);
            self.timeQueryCounter = 0;
            self.timeQueries.clear();
        }
    }

    pub fn enableStatsQuerys(self: *Cmd, gpi: vk.VkDevice) !void {
        if (self.statQueryPool != null) return;
        const poolInfo = vk.VkQueryPoolCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
            .queryType = vk.VK_QUERY_TYPE_PIPELINE_STATISTICS,
            .queryCount = rc.GPU_STATS_QUERYS,
            .pipelineStatistics = rc.STATS_MASK, // tells driver which counters to collect
        };
        var pool: vk.VkQueryPool = undefined;
        try vhF.check(vk.vkCreateQueryPool(gpi, &poolInfo, null, &pool), "Could not create Stats QueryPool");
        self.statQueryPool = pool;
    }

    pub fn disableStatsQuerys(self: *Cmd, gpi: vk.VkDevice) void {
        if (self.statQueryPool) |pool| {
            vk.vkDestroyQueryPool(gpi, pool, null);
            self.statQueryPool = null;
        }
    }

    pub fn resetStatsQuerys(self: *Cmd) void {
        if (self.statQueryPool) |pool| {
            vk.vkCmdResetQueryPool(self.handle, pool, 0, rc.GPU_STATS_QUERYS);
            self.statQueries.clear();
            self.activeStatQuery = null;
        }
    }

    pub fn startStatistics(self: *Cmd, name: []const u8) void {
        if (self.statQueryPool) |pool| {
            if (self.activeStatQuery) |_| {
                std.debug.print("Cmd Error: Stats query already active\n", .{});
            } else {
                const index: u8 = @intCast(self.statQueries.len);
                if (self.statQueries.len >= rc.GPU_STATS_QUERYS) {
                    std.debug.print("Stats slots full\n", .{});
                    return;
                }
                vk.vkCmdBeginQuery(self.handle, pool, index, 0);
                self.activeStatQuery = .{ .name = name, .typ = .Other, .startIndex = index };
            }
        }
    }

    pub fn endStatistics(self: *Cmd) void {
        if (self.statQueryPool) |pool| {
            const index = self.statQueries.len;
            if (index >= rc.GPU_STATS_QUERYS) {
                std.debug.print("GPU Stat Querys full\n", .{});
                return;
            }

            if (self.activeStatQuery) |activeStatQuery| {
                const statQuery = activeStatQuery;
                vk.vkCmdEndQuery(self.handle, pool, statQuery.startIndex);
                self.statQueries.append(statQuery) catch std.debug.print("ERROR: Could not append Stat Query\n", .{});
                self.activeStatQuery = null;
            } else {
                std.debug.print("Cmd Error: No active stats query to end\n", .{});
            }
        }
    }

    pub fn printStatsResults(self: *Cmd, gpi: vk.VkDevice) !void {
        const pool = self.statQueryPool orelse return;
        const count: u32 = @intCast(self.statQueries.len);
        if (count == 0) return;

        const statCount = @popCount(rc.STATS_MASK);

        // results layout: [slot0_stat0, slot0_stat1, ..., slot1_stat0, ...]
        var results: [rc.GPU_STATS_QUERYS * statCount]u64 = undefined;
        const stride = @sizeOf(u64) * statCount; // stride per slot
        const flags = vk.VK_QUERY_RESULT_64_BIT; // | vk.VK_QUERY_RESULT_WAIT_BIT
        const dataSize = @as(usize, count) * @as(usize, statCount) * @sizeOf(u64);
        try vhF.check(vk.vkGetQueryPoolResults(gpi, pool, 0, count, dataSize, &results, stride, flags), "Failed getting Stats Query results");

        // Ordered by Vulkan spec bit position — must match STATS_MASK bit order
        const statLabels = [13]struct { bit: u32, name: []const u8 }{
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_INPUT_ASSEMBLY_VERTICES_BIT, .name = "Input Assembly Vertices" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_INPUT_ASSEMBLY_PRIMITIVES_BIT, .name = "Input Assembly Primitives" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_VERTEX_SHADER_INVOCATIONS_BIT, .name = "Vertex Invocations" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_GEOMETRY_SHADER_INVOCATIONS_BIT, .name = "Geometry Invocations" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_GEOMETRY_SHADER_PRIMITIVES_BIT, .name = "Geometry Primitives" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_CLIPPING_INVOCATIONS_BIT, .name = "Clipping Invocations" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_CLIPPING_PRIMITIVES_BIT, .name = "Clipping Primitives" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_FRAGMENT_SHADER_INVOCATIONS_BIT, .name = "Fragment Invocations" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_TESSELLATION_CONTROL_SHADER_PATCHES_BIT, .name = "Tesselation Control Patches" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_TESSELLATION_EVALUATION_SHADER_INVOCATIONS_BIT, .name = "Tesselation Evaluation Invocations" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_COMPUTE_SHADER_INVOCATIONS_BIT, .name = "Compute Invocations" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_TASK_SHADER_INVOCATIONS_BIT_EXT, .name = "Task5 Invocations" },
            .{ .bit = vk.VK_QUERY_PIPELINE_STATISTIC_MESH_SHADER_INVOCATIONS_BIT_EXT, .name = "Mesh Invocations" },
        };

        std.debug.print("Pipeline Stats ({} passes):\n", .{count});
        for (self.statQueries.constSlice()) |query| {
            std.debug.print(" {s}:\n", .{query.name});
            var resultIndex: u8 = 0;
            for (statLabels) |def| {
                if (rc.STATS_MASK & @as(u32, @bitCast(def.bit)) != 0) {
                    std.debug.print("   {d}: {s}\n", .{ results[query.startIndex * statCount + resultIndex], def.name });
                    resultIndex += 1;
                }
            }
        }
        std.debug.print("Graphics State Changes: {}\n", .{self.stateChanges});
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

    pub fn blit(self: *const Cmd, srcImg: vk.VkImage, srcExtent: vk.VkExtent3D, dstImg: vk.VkImage, dstExtent: vk.VkExtent3D, dstOffset: vk.VkOffset3D, stretch: bool) void {
        const blitOffsets = calculateBlitOffsets(srcExtent, dstExtent, dstOffset, stretch);

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

    pub fn setViewportAndScissor(self: *const Cmd, x: f32, y: f32, width: f32, height: f32) void {
        const viewport = vk.VkViewport{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        vk.vkCmdSetViewportWithCount(self.handle, 1, &viewport);

        const scissor = vk.VkRect2D{
            .offset = .{ .x = @intFromFloat(x), .y = @intFromFloat(y) },
            .extent = .{ .width = @intFromFloat(width), .height = @intFromFloat(height) },
        };
        vk.vkCmdSetScissorWithCount(self.handle, 1, &scissor);
    }

    pub fn beginRendering(
        self: *const Cmd,
        width: u32,
        height: u32,
        colorInfs: []const vk.VkRenderingAttachmentInfo,
        depthInf: ?*const vk.VkRenderingAttachmentInfo,
        stencilInf: ?*const vk.VkRenderingAttachmentInfo,
    ) void {
        const scissor = vk.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = width, .height = height },
        };

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

    pub fn dispatchIndirect(self: *const Cmd, buffer: vk.VkBuffer, offset: u64) void {
        vk.vkCmdDispatchIndirect(self.handle, buffer, offset);
    }

    pub fn fillBuffer(self: *const Cmd, buffer: vk.VkBuffer, offset: u64, size: u64, data: u32) void {
        vk.vkCmdFillBuffer(self.handle, buffer, offset, size, data);
    }

    pub fn copyBuffer(self: *const Cmd, srcBuffer: vk.VkBuffer, transfer: Transfer, dstBuffer: vk.VkBuffer) void {
        const copy = vk.VkBufferCopy{ .srcOffset = transfer.srcOffset, .dstOffset = transfer.dstOffset, .size = transfer.size };
        vk.vkCmdCopyBuffer(self.handle, srcBuffer, dstBuffer, 1, &copy);
    }

    pub fn updateRenderState(self: *Cmd, new: RenderState) void {
        const cmd = self.handle;
        var stateChanges: u32 = 0;

        var cur: RenderState = undefined;
        var force = false;
        if (self.renderState) |renderState| cur = renderState else force = true;

        // Rasterization & Geometry
        if (force or cur.polygonMode != new.polygonMode) {
            vkFn.vkCmdSetPolygonModeEXT.?(cmd, new.polygonMode);
            stateChanges += 1;
        }
        if (force or cur.cullMode != new.cullMode) {
            vk.vkCmdSetCullMode(cmd, new.cullMode);
            stateChanges += 1;
        }
        if (force or cur.frontFace != new.frontFace) {
            vk.vkCmdSetFrontFace(cmd, new.frontFace);
            stateChanges += 1;
        }
        if (force or cur.topology != new.topology) {
            vk.vkCmdSetPrimitiveTopology(cmd, new.topology);
            stateChanges += 1;
        }

        if (force or cur.primitiveRestart != new.primitiveRestart) {
            vk.vkCmdSetPrimitiveRestartEnable(cmd, new.primitiveRestart);
            stateChanges += 1;
        }
        if (force or cur.rasterDiscard != new.rasterDiscard) {
            vk.vkCmdSetRasterizerDiscardEnable(cmd, new.rasterDiscard);
            stateChanges += 1;
        }
        if (force or cur.rasterSamples != new.rasterSamples) {
            vkFn.vkCmdSetRasterizationSamplesEXT.?(cmd, new.rasterSamples);
            stateChanges += 1;
        }

        const sampleMask: u32 = new.sample.sampleMask;
        if (force or !std.meta.eql(cur.sample, new.sample)) {
            vkFn.vkCmdSetSampleMaskEXT.?(cmd, new.sample.sampling, &sampleMask);
            stateChanges += 1;
        }

        // Depth & Stencil
        if (force or cur.depthBoundsTest != new.depthBoundsTest) {
            vk.vkCmdSetDepthBoundsTestEnable(cmd, new.depthBoundsTest);
            stateChanges += 1;
        }
        if (force or cur.depthBias != new.depthBias) {
            vk.vkCmdSetDepthBiasEnable(cmd, new.depthBias);
            stateChanges += 1;
        }
        if (force or cur.depthClamp != new.depthClamp) {
            vkFn.vkCmdSetDepthClampEnableEXT.?(cmd, new.depthClamp);
            stateChanges += 1;
        }

        if (force or cur.depthTest != new.depthTest) {
            vk.vkCmdSetDepthTestEnable(cmd, new.depthTest);
            stateChanges += 1;
        }
        if (force or cur.depthWrite != new.depthWrite) {
            vk.vkCmdSetDepthWriteEnable(cmd, new.depthWrite);
            stateChanges += 1;
        }
        if (force or cur.depthCompare != new.depthCompare) {
            vk.vkCmdSetDepthCompareOp(cmd, new.depthCompare);
            stateChanges += 1;
        }
        if (force or !std.meta.eql(cur.depthValues, new.depthValues)) {
            vk.vkCmdSetDepthBias(cmd, new.depthValues.constant, new.depthValues.clamp, new.depthValues.slope);
            stateChanges += 1;
        }

        if (force or cur.stencilTest != new.stencilTest) {
            vk.vkCmdSetStencilTestEnable(cmd, new.stencilTest);
            stateChanges += 1;
        }
        if (force or !std.meta.eql(cur.stencilOp, new.stencilOp)) {
            vk.vkCmdSetStencilOp(cmd, new.stencilOp[0], new.stencilOp[1], new.stencilOp[2], new.stencilOp[3], new.stencilOp[4]);
            stateChanges += 1;
        }
        if (force or !std.meta.eql(cur.stencilCompare, new.stencilCompare)) {
            vk.vkCmdSetStencilCompareMask(cmd, new.stencilCompare.faceMask, new.stencilCompare.mask);
            stateChanges += 1;
        }
        if (force or !std.meta.eql(cur.stencilWrite, new.stencilWrite)) {
            vk.vkCmdSetStencilWriteMask(cmd, new.stencilWrite.faceMask, new.stencilWrite.mask);
            stateChanges += 1;
        }
        if (force or !std.meta.eql(cur.stencilReference, new.stencilReference)) {
            vk.vkCmdSetStencilReference(cmd, new.stencilReference.faceMask, new.stencilReference.mask);
            stateChanges += 1;
        }

        // Color & Blending
        const blendEnable = new.colorBlend;
        const colorBlendAttachments = [_]vk.VkBool32{blendEnable} ** 8;
        if (force or cur.colorBlend != new.colorBlend) {
            vkFn.vkCmdSetColorBlendEnableEXT.?(cmd, 0, 8, &colorBlendAttachments);
            stateChanges += 1;
        }

        const oldBlendEquation = vk.VkColorBlendEquationEXT{
            .srcColorBlendFactor = cur.colorBlendEquation.srcColor,
            .dstColorBlendFactor = cur.colorBlendEquation.dstColor,
            .colorBlendOp = cur.colorBlendEquation.colorOperation,
            .srcAlphaBlendFactor = cur.colorBlendEquation.srcAlpha,
            .dstAlphaBlendFactor = cur.colorBlendEquation.dstAlpha,
            .alphaBlendOp = cur.colorBlendEquation.alphaOperation,
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
        if (force or !std.meta.eql(oldBlendEquation, blendEquation)) {
            vkFn.vkCmdSetColorBlendEquationEXT.?(cmd, 0, 8, &equations);
            stateChanges += 1;
        }

        const oldBlendConsts = [_]f32{ cur.blendConstants.red, cur.blendConstants.green, cur.blendConstants.blue, cur.blendConstants.alpha };
        const blendConsts = [_]f32{ new.blendConstants.red, new.blendConstants.green, new.blendConstants.blue, new.blendConstants.alpha };
        if (force or !std.meta.eql(oldBlendConsts, blendConsts)) {
            vk.vkCmdSetBlendConstants(cmd, &blendConsts);
            stateChanges += 1;
        }

        const colWriteMasks = [_]vk.VkColorComponentFlags{new.colorWriteMask} ** 8;
        if (force or cur.colorWriteMask != new.colorWriteMask) {
            vkFn.vkCmdSetColorWriteMaskEXT.?(cmd, 0, 8, &colWriteMasks);
            stateChanges += 1;
        }

        if (force or cur.alphaToOne != new.alphaToOne) {
            vkFn.vkCmdSetAlphaToOneEnableEXT.?(cmd, new.alphaToOne);
            stateChanges += 1;
        }
        if (force or cur.alphaToCoverage != new.alphaToCoverage) {
            vkFn.vkCmdSetAlphaToCoverageEnableEXT.?(cmd, new.alphaToCoverage);
            stateChanges += 1;
        }

        if (force or cur.logicOp != new.logicOp) {
            vkFn.vkCmdSetLogicOpEnableEXT.?(cmd, new.logicOp);
            stateChanges += 1;
        }
        if (force or cur.logicOpType != new.logicOpType) {
            vkFn.vkCmdSetLogicOpEXT.?(cmd, new.logicOpType);
            stateChanges += 1;
        }

        // Advanced / Debug
        if (force or cur.lineWidth != new.lineWidth) {
            vk.vkCmdSetLineWidth(cmd, new.lineWidth);
            stateChanges += 1;
        }
        if (force or cur.conservativeRasterMode != new.conservativeRasterMode) {
            vkFn.vkCmdSetConservativeRasterizationModeEXT.?(cmd, new.conservativeRasterMode);
            stateChanges += 1;
        }

        const combinerOps = [_]vk.VkFragmentShadingRateCombinerOpKHR{ new.fragShadingRate.operation, new.fragShadingRate.operation };
        const extent = vk.VkExtent2D{ .width = new.fragShadingRate.width, .height = new.fragShadingRate.height };
        if (force or !std.meta.eql(cur.fragShadingRate, new.fragShadingRate)) {
            vkFn.vkCmdSetFragmentShadingRateKHR.?(cmd, &extent, &combinerOps);
            stateChanges += 1;
        }

        self.stateChanges += stateChanges;
        self.renderState = new;
    }

    pub fn createSubmitInfo(self: *const Cmd) vk.VkCommandBufferSubmitInfo {
        return vk.VkCommandBufferSubmitInfo{ .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO, .commandBuffer = self.handle };
    }
};

fn createSubresourceLayers(mask: u32, mipLevel: u32, arrayLayer: u32, layerCount: u32) vk.VkImageSubresourceLayers {
    return vk.VkImageSubresourceLayers{ .aspectMask = mask, .mipLevel = mipLevel, .baseArrayLayer = arrayLayer, .layerCount = layerCount };
}

fn calculateBlitOffsets(srcExtent: vk.VkExtent3D, dstExtent: vk.VkExtent3D, dstOffset: vk.VkOffset3D, stretch: bool) struct { srcOffsets: [2]vk.VkOffset3D, dstOffsets: [2]vk.VkOffset3D } {
    var srcOffsets: [2]vk.VkOffset3D = undefined;
    var dstOffsets: [2]vk.VkOffset3D = undefined;

    if (stretch == true) {
        // Stretch: Source is full image, Dest is full window
        srcOffsets[0] = .{ .x = 0, .y = 0, .z = 0 };
        srcOffsets[1] = .{ .x = @intCast(srcExtent.width), .y = @intCast(srcExtent.height), .z = 1 };
        dstOffsets[0] = .{ .x = dstOffset.x, .y = dstOffset.y, .z = 0 };
        const winW: i32 = @intCast(dstExtent.width);
        const winH: i32 = @intCast(dstExtent.height);
        dstOffsets[1] = .{ .x = winW + dstOffset.x, .y = winH + dstOffset.y, .z = 1 };
    } else {
        // No Stretch (Center / Crop)
        const srcW: i32 = @intCast(srcExtent.width);
        const srcH: i32 = @intCast(srcExtent.height);
        const winW: i32 = @intCast(dstExtent.width);
        const winH: i32 = @intCast(dstExtent.height);
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
        dstOffsets[0] = .{ .x = dstX + dstOffset.x, .y = dstY + dstOffset.y, .z = 0 };

        dstOffsets[1] = .{ .x = dstX + blitW + dstOffset.x, .y = dstY + blitH + dstOffset.y, .z = 1 };
    }
    return .{ .srcOffsets = srcOffsets, .dstOffsets = dstOffsets };
}
