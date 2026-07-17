// const PassExecution = @import("../types/pass/PassInstance.zig").PassExecution;
const CompositeNode = @import("../types/pass/RenderNode.zig").CompositeNode;
const RenderNode = @import("../types/pass/RenderNode.zig").RenderNode;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const UiNode = @import("../types/pass/RenderNode.zig").UiNode;
const SwapchainMan = @import("SwapchainMan.zig").SwapchainMan;
const Texture = @import("../types/res/Texture.zig").Texture;
const ResourceMan = @import("ResourceMan.zig").ResourceMan;
const TexId = @import("../../.configs/idConfig.zig").TexId;
const BufId = @import("../../.configs/idConfig.zig").BufId;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const ShaderManager = @import("ShaderMan.zig").ShaderMan;
const rc = @import("../../.configs/renderConfig.zig");
const sc = @import("../../.configs/shaderConfig.zig");
const FrameData = @import("../../App.zig").FrameData;
const Cmd = @import("../types/base/Cmd.zig").Cmd;
const CmdManager = @import("CmdMan.zig").CmdMan;
const Context = @import("Context.zig").Context;
const vk = @import("../../.modules/vk.zig").c;
const vhT = @import("../help/Types.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const VertexBufferFill = @import("../types/pass/VertexBufferUse.zig").VertexBufferFill;
const VertexAttribute = @import("../types/pass/VertexAttribute.zig").VertexAttribute;
const IndexBufferFill = @import("../types/pass/IndexBufferUse.zig").IndexBufferFill;
const ShaderId = @import("../../.configs/idConfig.zig").ShaderId;
// const AttachmentFill = @import("AttachmentFill.zig").AttachmentFill;
const RenderState = @import("../types/pass/RenderState.zig").RenderState;
// const TextureFill = @import("TextureFill.zig").TextureFill;
const String = @import("../../globalHelper.zig").String;
// const BufferFill = @import("BufferFill.zig").BufferFill;

pub const CmdState = struct {
    outputWidth: ?u32 = null,
    outputHeight: ?u32 = null,
    //
    shaderIds: FixedList(ShaderId, 3) = .{},
    //
    pushDataLen: u32 = 0,
    pushData: [128]u8 = .{0} ** 128,
    //
    renderState: RenderState = .{},
    //
    colorAtts: FixedList(vk.VkRenderingAttachmentInfo, 8) = .{},
    depthAtt: ?vk.VkRenderingAttachmentInfo = null,
    stencilAtt: ?vk.VkRenderingAttachmentInfo = null,
    //
    indexBuffer: ?IndexBufferFill = null,
    vertexBuffers: FixedList(VertexBufferFill, 4) = .{},
    vertexAttributes: FixedList(VertexAttribute, 16) = .{},
};

pub const CmdRecorder = struct {
    alloc: Allocator,
    gpi: vk.VkDevice,
    cmdMan: CmdManager,
    imgBarriers: std.array_list.Managed(vk.VkImageMemoryBarrier2),
    bufBarriers: std.array_list.Managed(vk.VkBufferMemoryBarrier2),
    imgClears: std.array_list.Managed(TexId),
    bufClears: std.array_list.Managed(BufId),
    memSrcStage: vk.VkPipelineStageFlags2 = 0,
    memSrcAccess: vk.VkAccessFlags2 = 0,
    memDstStage: vk.VkPipelineStageFlags2 = 0,
    memDstAccess: vk.VkAccessFlags2 = 0,
    useGpuTimers: bool = false,
    useGpuStats: bool = false,

    state: CmdState = .{}, // Per Pass State

    pub fn init(alloc: Allocator, context: *const Context) !CmdRecorder {
        return .{
            .alloc = alloc,
            .gpi = context.gpi,
            .cmdMan = try CmdManager.init(alloc, context, rc.MAX_IN_FLIGHT),
            .imgBarriers = try std.array_list.Managed(vk.VkImageMemoryBarrier2).initCapacity(alloc, rc.MAX_PASS_ATTRIBUTES),
            .bufBarriers = try std.array_list.Managed(vk.VkBufferMemoryBarrier2).initCapacity(alloc, rc.MAX_PASS_ATTRIBUTES),
            .imgClears = try std.array_list.Managed(TexId).initCapacity(alloc, rc.MAX_PASS_ATTRIBUTES),
            .bufClears = try std.array_list.Managed(BufId).initCapacity(alloc, rc.MAX_PASS_ATTRIBUTES),
        };
    }

    pub fn deinit(self: *CmdRecorder) void {
        self.imgBarriers.deinit();
        self.bufBarriers.deinit();
        self.imgClears.deinit();
        self.bufClears.deinit();
        self.cmdMan.deinit();
    }

    pub fn toggleGpuProfiling(self: *CmdRecorder) void {
        if (rc.GPU_TIMERS == true) {
            if (self.useGpuTimers == true) self.useGpuTimers = false else self.useGpuTimers = true;
        }
        if (rc.GPU_STATS == true) {
            if (self.useGpuStats == true) self.useGpuStats = false else self.useGpuStats = true;
        }
    }

    pub fn recordFrame(
        self: *CmdRecorder,
        renderNodes: []RenderNode,
        flightId: u8,
        frame: u64,
        swapMan: *SwapchainMan,
        resMan: *ResourceMan,
        shaderMan: *ShaderManager,
        _: bool,
        pushData: []const u8,
    ) !*Cmd {
        var cmd = try self.cmdMan.getCmd(flightId);
        try cmd.begin(flightId, frame);

        if (self.useGpuTimers == true and frame % rc.GPU_QUERY_INTERVAL == 0) try cmd.enableTimeQuerys(self.gpi) else cmd.disableTimeQuerys(self.gpi);
        cmd.resetTimeQuerys();

        if (self.useGpuStats == true and frame % rc.GPU_QUERY_INTERVAL == 0) try cmd.enableStatsQuerys(self.gpi) else cmd.disableStatsQuerys(self.gpi);
        cmd.resetStatsQuerys();

        const timeId = cmd.startTimer(.TopOfPipe, "Descriptor Heap Bind", .Other);
        cmd.bindDescriptorHeap(resMan.descMan.descHeap.gpuAddress, resMan.descMan.descHeap.size, resMan.descMan.driverReservedSize);
        cmd.bindSamplerHeap(resMan.descMan.samplerHeap.gpuAddress, resMan.descMan.samplerHeap.size, resMan.descMan.samplerReservedSize);
        cmd.endTimer(.BotOfPipe, timeId);

        try self.recordTransfers(cmd, resMan);
        try self.recordNodes(cmd, renderNodes, resMan, shaderMan, swapMan, pushData);
        try self.recordPresentation(cmd, swapMan);

        try cmd.end();
        return cmd;
    }

    fn recordTransfers(self: *CmdRecorder, cmd: *Cmd, resMan: *ResourceMan) !void {
        var resUpdater = &resMan.updater;
        const stagingBuf = resUpdater.getStagingBuffer(cmd.flightId);

        const fullTransfers = resUpdater.getFullUpdates(cmd.flightId);
        if (fullTransfers.len != 0) {
            const timeId = cmd.startTimer(.TopOfPipe, "Full Transfers", .Other);

            for (fullTransfers) |transfer| {
                const buffer = try resMan.get(transfer.dstResId, cmd.flightId);
                try self.checkBufferState(buffer, .{ .stage = .Transfer, .access = .TransferWrite });
            }

            self.bakeBarriers(cmd, "Full Transfers Prep");

            for (fullTransfers) |transfer| {
                const buffer = try resMan.get(transfer.dstResId, cmd.flightId);
                cmd.copyBuffer(stagingBuf, transfer, buffer.handle);
            }
            cmd.endTimer(.BotOfPipe, timeId);
        }

        const partialTransfers = resUpdater.getSegmentUpdates(cmd.flightId);
        if (partialTransfers.len != 0) {
            const timeId = cmd.startTimer(.TopOfPipe, "Partial Transfers", .Other);

            for (partialTransfers) |transfer| {
                const buffer = try resMan.get(transfer.dstResId, cmd.flightId);
                try self.checkBufferState(buffer, .{ .stage = .Transfer, .access = .TransferWrite });
            }

            self.bakeBarriers(cmd, "Segment Transfers Prep");

            for (partialTransfers) |transfer| {
                const buffer = try resMan.get(transfer.dstResId, cmd.flightId);
                cmd.copyBuffer(stagingBuf, transfer, buffer.handle);
            }
            cmd.endTimer(.BotOfPipe, timeId);
        }

        // textures
        const texTransfers = resUpdater.getTexUpdates(cmd.flightId);
        if (texTransfers.len != 0) {
            const timeId = cmd.startTimer(.TopOfPipe, "Texture Transfers", .Other);

            for (texTransfers) |transfer| {
                const tex = try resMan.get(transfer.dstTexId, cmd.flightId);
                try self.checkImageState(tex, .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst });
            }
            self.bakeBarriers(cmd, "Tex Transfer Prep");

            for (texTransfers) |transfer| {
                const tex = try resMan.get(transfer.dstTexId, cmd.flightId);
                cmd.copyBufferToImage(stagingBuf, tex.img, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, transfer.width, transfer.height, transfer.srcOffset);
            }
            cmd.endTimer(.BotOfPipe, timeId);
        }

        resUpdater.resetUpdates(cmd.flightId);
    }

    fn checkImageState(self: *CmdRecorder, tex: *Texture, neededState: Texture.TextureState) !void {
        const state = tex.state;
        if (state.stage == neededState.stage and state.access == neededState.access and state.layout == neededState.layout) return;
        if (state.layout == neededState.layout and state.access.isReadOnly() and neededState.access.isReadOnly()) return; // same layout, both reads

        const layoutTransition = if (state.layout != neededState.layout) true else false;

        if (rc.USE_MEM_BARRIER_ON_IMAGES == true and layoutTransition == false) {
            const memBarrier = tex.createMemoryBarrier(neededState);
            self.memSrcAccess |= memBarrier.srcAccessMask;
            self.memSrcStage |= memBarrier.srcStageMask;
            self.memDstAccess |= memBarrier.dstAccessMask;
            self.memDstStage |= memBarrier.dstStageMask;
        } else {
            try self.imgBarriers.append(tex.createImageBarrier(neededState));
        }
    }

    fn checkBufferState(self: *CmdRecorder, buffer: *Buffer, neededState: Buffer.BufferState) !void {
        const state = buffer.state;
        if (state.stage == neededState.stage and state.access == neededState.access) return;
        if (state.access.isReadOnly() and neededState.access.isReadOnly()) return;

        if (rc.USE_MEM_BARRIERS_ON_BUFFERS) {
            const memBarrier = buffer.createMemoryBarrier(neededState);
            self.memSrcAccess |= memBarrier.srcAccessMask;
            self.memSrcStage |= memBarrier.srcStageMask;
            self.memDstAccess |= memBarrier.dstAccessMask;
            self.memDstStage |= memBarrier.dstStageMask;
        } else {
            try self.bufBarriers.append(buffer.createBufferBarrier(neededState));
        }
    }

    fn recordNodes(self: *CmdRecorder, cmd: *Cmd, renderNodes: []RenderNode, resMan: *ResourceMan, shaderMan: *ShaderManager, swapMan: *SwapchainMan, pushData: []const u8) !void {
        for (renderNodes) |renderNode| {
            switch (renderNode) {
                .passPrint => {},
                .compositePrint => {},
                .uiPrint => {},

                // Graph Commands
                .clearBuffer => |clearBufId| {
                    const buffer: *Buffer = try resMan.get(clearBufId, cmd.flightId);
                    try self.checkBufferState(buffer, .{ .stage = .Transfer, .access = .TransferWrite });
                    try self.bufClears.append(clearBufId);
                },
                .clearTexture => |clearTexId| {
                    const texture: *Texture = try resMan.get(clearTexId, cmd.flightId);
                    try self.checkImageState(texture, .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst });
                    try self.imgClears.append(clearTexId);
                },
                .barrierBakeClears => try self.bakeAndExecuteClears(cmd, resMan),

                // Profiling Commands
                .startTimer => |startTimer| {
                    try cmd.startTimerWithId(.TopOfPipe, startTimer.name.get(), startTimer.typ, startTimer.queryId);
                },
                .endTimer => |endTimer| {
                    cmd.endTimer(endTimer.pipeStage, endTimer.queryId);
                },
                .startStats => |startStats| {
                    cmd.startStatistics(startStats.get());
                },
                .endStats => {
                    cmd.endStatistics();
                },

                // Barrier Commands
                .bufBarrier => |bufBarrier| {
                    const buf = try resMan.get(bufBarrier.bufId, cmd.flightId);
                    try self.checkBufferState(buf, .{ .stage = bufBarrier.stage, .access = bufBarrier.access });
                },
                .texBarrier => |texBarrier| {
                    const tex = try resMan.get(texBarrier.texId, cmd.flightId);
                    try self.checkImageState(tex, .{ .stage = texBarrier.stage, .access = texBarrier.access, .layout = texBarrier.layout });
                },
                .swapchainTargetBarrier => |targetBarrier| {
                    const targetIndex = swapMan.getTargetIndex(targetBarrier.windowId) orelse {
                        std.debug.print("swapchainTargetBarrier: no swapchain target for window {}\n", .{targetBarrier.windowId.val()});
                        return;
                    };
                    const swapchain = swapMan.getTargetByIndex(targetIndex);
                    const targetTex = swapchain.getCurTexture();
                    try self.checkImageState(targetTex, .{ .stage = targetBarrier.stage, .access = targetBarrier.access, .layout = targetBarrier.layout });
                },
                .bakeBarriers => {
                    self.bakeBarriers(cmd, "Bake Pass Barriers");
                },

                // Pass Commands
                .setShader => |shaderId| {
                    self.state.shaderIds.append(shaderId) catch return error.CmdStateShaderIdFull;
                },
                .bindShaders => {
                    const shaders = shaderMan.getShaders(self.state.shaderIds.constSlice());
                    cmd.bindShaders(shaders[0..self.state.shaderIds.constSlice().len]);
                },
                .setPushData => |pushInf| {
                    std.debug.assert(pushInf.len <= 128);
                    std.debug.assert(pushInf.offset + pushInf.len <= 128);

                    const destSlice = self.state.pushData[pushInf.offset .. pushInf.offset + pushInf.len];
                    const srcSlice = pushData[pushInf.startIndex .. pushInf.startIndex + pushInf.len];

                    @memcpy(destSlice, srcSlice);
                    self.state.pushDataLen = @max(self.state.pushDataLen, pushInf.len + pushInf.offset);
                },
                .setPushDataBufDesc => |push| {
                    std.debug.assert(push.size <= 128);
                    std.debug.assert(push.offset + push.size <= 128);

                    const bufDesc = try resMan.getBufferDescriptor(push.bufId, cmd.flightId);
                    const src = std.mem.asBytes(&bufDesc)[0..push.size]; // desc is u32

                    @memcpy(self.state.pushData[push.offset..][0..push.size], src);
                    self.state.pushDataLen = @max(self.state.pushDataLen, push.size + push.offset);
                },
                .setPushDataTexDesc => |push| {
                    std.debug.assert(push.size <= 128);
                    std.debug.assert(push.offset + push.size <= 128);

                    const texDesc = try resMan.getTextureDescriptor(push.texId, cmd.flightId, push.descTyp);
                    const src = std.mem.asBytes(&texDesc)[0..push.size]; // desc is u32

                    @memcpy(self.state.pushData[push.offset..][0..push.size], src);
                    self.state.pushDataLen = @max(self.state.pushDataLen, push.size + push.offset);
                },
                .setPushDataOutputExtent => |push| {
                    const width: u32 = self.state.outputWidth orelse 0;
                    const height: u32 = self.state.outputHeight orelse 0;
                    @memcpy(self.state.pushData[push.offset..][0..4], std.mem.asBytes(&width));
                    @memcpy(self.state.pushData[push.offset + 4 ..][0..4], std.mem.asBytes(&height));
                    self.state.pushDataLen = @max(self.state.pushDataLen, push.offset + 8);
                },
                .bindPushData => {
                    // cmd.setPushData(&self.state.pushData, self.state.pushDataLen, 0);
                    cmd.setPushData(&self.state.pushData, @sizeOf([128]u8), 0); // CURRENTLY USING FULL 128 BYTES!
                },

                .dispatch => |dispatch| {
                    cmd.dispatch(dispatch.groupX, dispatch.groupY, dispatch.groupZ);
                },
                .dispatchOutputTex => |dispatchImg| {
                    const tex = try resMan.get(dispatchImg.texId, cmd.flightId);
                    const extent = tex.extent;
                    cmd.dispatch(
                        (extent.width + dispatchImg.groupX - 1) / dispatchImg.groupX,
                        (extent.height + dispatchImg.groupY - 1) / dispatchImg.groupY,
                        (extent.depth + dispatchImg.groupZ - 1) / dispatchImg.groupZ,
                    );
                },
                .dispatchIndirect => |dispatchIndirect| {
                    const buffer = try resMan.get(dispatchIndirect.indirectBufId, cmd.flightId);
                    cmd.dispatchIndirect(buffer.handle, dispatchIndirect.indirectBufOffset);
                },

                .setOutputExtentSwapchain => |output| {
                    const targetIndex = swapMan.getTargetIndex(output) orelse {
                        std.debug.print("beginRenderingSwapchain: no swapchain target for window {}\n", .{output.val()});
                        return;
                    };
                    const swapchain = swapMan.getTargetByIndex(targetIndex);
                    const targetTex = swapchain.getCurTexture();
                    self.state.outputWidth = targetTex.extent.width;
                    self.state.outputHeight = targetTex.extent.height;
                },
                .setOutputExtent => |output| {
                    if (output) |outputTexId| {
                        const tex = try resMan.get(outputTexId, cmd.flightId);
                        self.state.outputWidth = tex.extent.width;
                        self.state.outputHeight = tex.extent.height;
                    }
                },

                .beginRendering => {
                    const outputWidth = self.state.outputWidth orelse return error.CmdStateOutputWidthMissing;
                    const outputHeight = self.state.outputHeight orelse return error.CmdStateOutputHeightMissing;
                    const depthAtt = if (self.state.depthAtt) |*depthAtt| depthAtt else null;
                    const stencilAtt = if (self.state.stencilAtt) |*stencilAtt| stencilAtt else null;
                    cmd.beginRendering(outputWidth, outputHeight, self.state.colorAtts.constSlice(), depthAtt, stencilAtt);
                },

                .setViewportFromOutput => {
                    cmd.setViewport(0, 0, @floatFromInt(self.state.outputWidth orelse 0), @floatFromInt(self.state.outputHeight orelse 0));
                },
                .setScissorFromOutput => {
                    cmd.setScissor(0, 0, @floatFromInt(self.state.outputWidth orelse 0), @floatFromInt(self.state.outputHeight orelse 0));
                },
                .setViewportFromTex => |texViewport| {
                    const tex = try resMan.get(texViewport, cmd.flightId);
                    cmd.setViewport(0, 0, @floatFromInt(tex.extent.width), @floatFromInt(tex.extent.height));
                },
                .setScissorFromTex => |texScissor| {
                    const tex = try resMan.get(texScissor, cmd.flightId);
                    cmd.setScissor(0, 0, @floatFromInt(tex.extent.width), @floatFromInt(tex.extent.height));
                },
                .setViewport => |viewport| {
                    cmd.setViewport(viewport.x, viewport.y, viewport.width, viewport.height);
                },
                .setScissor => |scissor| {
                    cmd.setScissor(scissor.x, scissor.y, scissor.width, scissor.height);
                },
                .setRenderStateUnion => |state| {
                    switch (state) {
                        inline else => |val, tag| @field(self.state.renderState, @tagName(tag)) = val,
                    }
                },
                .bindRenderState => {
                    cmd.updateRenderState(self.state.renderState);
                },

                .setColorAttSwapchain => |swapchainAtt| {
                    const targetIndex = swapMan.getTargetIndex(swapchainAtt) orelse {
                        std.debug.print("beginRenderingSwapchain: no swapchain target for window {}\n", .{swapchainAtt.val()});
                        return;
                    };
                    const swapchain = swapMan.getTargetByIndex(targetIndex);
                    const targetTex = swapchain.getCurTexture();
                    const isFirstUse = targetTex.state.layout == .Undefined;
                    const colorAtt = try targetTex.createAttachment(.Swapchain, if (isFirstUse) .{ .color = rc.INITIAL_SWAPCHAIN_COLOR } else null);

                    self.state.colorAtts.append(colorAtt) catch return error.CmdStateColorAttsFull;
                },
                .setColorAtt => |setColorAtt| {
                    const texMeta = try resMan.getMeta(setColorAtt.texId);
                    const tex = try resMan.get(setColorAtt.texId, cmd.flightId);
                    const colorAtt = try tex.createAttachment(texMeta.typ, if (setColorAtt.clear) |clear| .{ .color = clear } else null);

                    self.state.colorAtts.append(colorAtt) catch return error.CmdStateColorAttsFull;
                },
                .setDepthAtt => |depth| {
                    const texMeta = try resMan.getMeta(depth.texId);
                    const tex = try resMan.get(depth.texId, cmd.flightId);
                    const depthAtt = try tex.createAttachment(texMeta.typ, if (depth.clear) |clear| .{ .depth = clear } else null);

                    self.state.depthAtt = depthAtt;
                },
                .setStencilAtt => |stencil| {
                    const texMeta = try resMan.getMeta(stencil.texId);
                    const tex = try resMan.get(stencil.texId, cmd.flightId);
                    const stencilAtt = try tex.createAttachment(texMeta.typ, if (stencil.clear) |clear| .{ .depth = clear } else null);

                    self.state.stencilAtt = stencilAtt;
                },

                .setIndexBuf => |indexBuf| {
                    // const buffer = try resMan.get(indexBuf.bufId, cmd.flightId);
                    self.state.indexBuffer = indexBuf;
                },
                .setVertexBuf => |vertBuf| {
                    self.state.vertexBuffers.append(vertBuf) catch return error.CmdStateVertexBuffersFull;
                },
                .setVertexAttrib => |attrib| {
                    self.state.vertexAttributes.append(attrib) catch return error.CmdStateVertexAttributesFull;
                },
                .bindIndexInput => {
                    if (self.state.indexBuffer) |indexBuffer| {
                        const buffer = try resMan.get(indexBuffer.bufId, cmd.flightId);
                        cmd.bindIndexBuffer(buffer.handle, 0, indexBuffer.indexType);
                    }
                },
                .bindVertexInput => {
                    if (self.state.vertexBuffers.len == 0) {
                        cmd.setVertexInput(null, null);
                    } else {
                        var bindingDescs: [4]vk.VkVertexInputBindingDescription2EXT = undefined;
                        for (self.state.vertexBuffers.constSlice(), 0..) |vbUse, i| {
                            bindingDescs[i] = .{
                                .sType = vk.VK_STRUCTURE_TYPE_VERTEX_INPUT_BINDING_DESCRIPTION_2_EXT,
                                .binding = vbUse.binding,
                                .stride = vbUse.stride,
                                .inputRate = vbUse.inputRate,
                                .divisor = 1,
                            };
                        }
                        var attrDescs: [16]vk.VkVertexInputAttributeDescription2EXT = undefined;
                        for (self.state.vertexAttributes.constSlice(), 0..) |attr, i| {
                            attrDescs[i] = .{
                                .sType = vk.VK_STRUCTURE_TYPE_VERTEX_INPUT_ATTRIBUTE_DESCRIPTION_2_EXT,
                                .location = attr.location,
                                .binding = attr.binding,
                                .format = attr.format,
                                .offset = attr.offset,
                            };
                        }
                        cmd.setVertexInput(bindingDescs[0..self.state.vertexBuffers.len], attrDescs[0..self.state.vertexAttributes.len]);

                        var bufHandles: [4]vk.VkBuffer = undefined;
                        var bufOffsets: [4]vk.VkDeviceSize = .{0} ** 4;

                        for (self.state.vertexBuffers.constSlice(), 0..) |vbUse, i| {
                            bufHandles[i] = (try resMan.get(vbUse.bufId, cmd.flightId)).handle;
                        }
                        cmd.bindVertexBuffers(0, bufHandles[0..self.state.vertexBuffers.len], bufOffsets[0..self.state.vertexBuffers.len]);
                    }
                },

                .drawVertex => |drawVertex| {
                    cmd.draw(drawVertex.vertexCount, drawVertex.instanceCount, drawVertex.firstVertex, drawVertex.firstInstance);
                },
                .drawVertexIndexed => |drawIndexed| {
                    cmd.drawIndexed(drawIndexed.indexCount, drawIndexed.instanceCount, drawIndexed.firstIndex, drawIndexed.vertexOffset, drawIndexed.firstInstance);
                },
                .drawTaskOrMesh => |drawTaskOrMesh| {
                    cmd.drawMeshTasks(drawTaskOrMesh.groupX, drawTaskOrMesh.groupY, drawTaskOrMesh.groupZ);
                },
                .drawTaskOrMeshIndirect => |drawTasksOrMeshIndirect| {
                    const buffer = try resMan.get(drawTasksOrMeshIndirect.indirectBufId, cmd.flightId);
                    cmd.drawMeshTasksIndirect(buffer.handle, drawTasksOrMeshIndirect.bufOffset, drawTasksOrMeshIndirect.drawCount, drawTasksOrMeshIndirect.stride);
                },

                .endRendering => {
                    cmd.endRendering();
                },

                .resetState => {
                    self.state = .{};
                },
            }
        }
    }

    fn bakeAndExecuteClears(self: *CmdRecorder, cmd: *Cmd, resMan: *ResourceMan) !void {
        self.bakeBarriers(cmd, "Clear Barrier");

        for (self.imgClears.items) |texId| {
            const texture: *Texture = try resMan.get(texId, cmd.flightId);
            switch (texture.typ) {
                .Color16, .Color8, .Swapchain => cmd.clearColorImage(texture.img, 0.0, 0.0, 0.0, 0.0), // Maybe alpha should be 1 ??
                .Depth32, .Stencil8 => cmd.clearDepthImage(texture.img, 0.0, 0.0),
            }
        }
        self.imgClears.clearRetainingCapacity();

        for (self.bufClears.items) |bufId| {
            const buffer: *Buffer = try resMan.get(bufId, cmd.flightId);
            cmd.fillBuffer(buffer.handle, 0, vk.VK_WHOLE_SIZE, 0);
        }
        self.bufClears.clearRetainingCapacity();
    }

    fn recordPresentation(self: *CmdRecorder, cmd: *Cmd, swapMan: *SwapchainMan) !void {
        const timeId = cmd.startTimer(.TopOfPipe, "Presentation", .Other);

        const targetIndices = swapMan.getTargetsIndices();
        for (targetIndices) |index| {
            const swapchain = swapMan.getTargetByIndex(index);
            const target = swapchain.getCurTexture();
            try self.checkImageState(target, .{ .stage = .BotOfPipe, .access = .None, .layout = .PresentSrc });
        }
        self.bakeBarriers(cmd, "Present Transition");
        cmd.endTimer(.BotOfPipe, timeId);
    }

    fn bakeBarriers(self: *CmdRecorder, cmd: *const Cmd, name: []const u8) void {
        const imgBarrierCount = self.imgBarriers.items.len;
        const bufBarrierCount = self.bufBarriers.items.len;
        const hasMemBarrier = self.memSrcStage != 0;

        if (imgBarrierCount != 0 or bufBarrierCount != 0 or hasMemBarrier) {
            if (rc.BARRIER_DEBUG) std.debug.print("BakeBarriers: {} Img, {} Buf ({s})\n", .{ imgBarrierCount, bufBarrierCount, name });

            if (hasMemBarrier) {
                const memBarrier = vk.VkMemoryBarrier2{
                    .sType = vk.VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
                    .srcStageMask = self.memSrcStage,
                    .srcAccessMask = self.memSrcAccess,
                    .dstStageMask = self.memDstStage,
                    .dstAccessMask = self.memDstAccess,
                };
                cmd.bakeBarriers(self.imgBarriers.items, self.bufBarriers.items, &.{memBarrier});
                self.memSrcStage = 0;
                self.memSrcAccess = 0;
                self.memDstStage = 0;
                self.memDstAccess = 0;
            } else {
                cmd.bakeBarriers(self.imgBarriers.items, self.bufBarriers.items, &.{});
            }

            self.imgBarriers.clearRetainingCapacity();
            self.bufBarriers.clearRetainingCapacity();
        } else if (rc.BARRIER_DEBUG) std.debug.print("BakeBarriers: Skipped ({s})\n", .{name});
    }
};
