const RenderNodeRing = @import("../../renderCompiler/RenderCompilerData.zig").RenderCompilerData.RenderNodeRing;
const VertexBufferUse = @import("../types/pass/VertexBufferUse.zig").VertexBufferUse;
const VertexAttribute = @import("../types/pass/VertexAttribute.zig").VertexAttribute;
const IndexBufferUse = @import("../types/pass/IndexBufferUse.zig").IndexBufferUse;
const CompositeNode = @import("../types/pass/RenderNode.zig").CompositeNode;
const ClearValue = @import("../types/pass/AttachmentUse.zig").ClearValue;
const RenderState = @import("../types/pass/RenderState.zig").RenderState;
const SimpleTexture = @import("../types/res/Texture.zig").SimpleTexture;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const RenderNode = @import("../types/pass/RenderNode.zig").RenderNode;
const TextureState = @import("../types/res/Texture.zig").TextureState;
const BufferState = @import("../types/res/Buffer.zig").BufferState;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const ShaderId = @import("../../.configs/idConfig.zig").ShaderId;
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
const vhF = @import("../help/Functions.zig");
const vhE = @import("../help/Enums.zig");
const vhT = @import("../help/Types.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

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
    indexBuffer: ?IndexBufferUse = null,
    vertexBuffers: FixedList(VertexBufferUse, 4) = .{},
    vertexAttributes: FixedList(VertexAttribute, 16) = .{},
};

pub const CmdRecorder = struct {
    alloc: Allocator,
    gpi: vk.VkDevice,
    cmdMan: CmdManager,
    imgBarriers: std.array_list.Managed(vk.VkImageMemoryBarrier2),
    bufBarriers: std.array_list.Managed(vk.VkBufferMemoryBarrier2),
    memBarrier: ?vk.VkMemoryBarrier2 = null,
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
        };
    }

    pub fn deinit(self: *CmdRecorder) void {
        self.imgBarriers.deinit();
        self.bufBarriers.deinit();
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

    pub fn recordFrame(self: *CmdRecorder, renderNodes: *const RenderNodeRing, flightId: u8, frame: u64, swapMan: *SwapchainMan, resMan: *ResourceMan, shaderMan: *ShaderManager, _: bool, pushData: []const u8) !*Cmd {
        var cmd = try self.cmdMan.getCmd(flightId);
        try cmd.begin(flightId, frame);

        if (self.useGpuTimers == true and frame % rc.GPU_QUERY_INTERVAL == 0) try cmd.enableTimeQuerys(self.gpi) else cmd.disableTimeQuerys(self.gpi);
        cmd.resetTimeQuerys();

        if (self.useGpuStats == true and frame % rc.GPU_QUERY_INTERVAL == 0) try cmd.enableStatsQuerys(self.gpi) else cmd.disableStatsQuerys(self.gpi);
        cmd.resetStatsQuerys();

        const timeId = cmd.startTimer(.AllCmds, "Descriptor Heap Bind", .Other);
        cmd.bindDescriptorHeap(resMan.descMan.descHeap.gpuAddress, resMan.descMan.descHeap.size, resMan.descMan.driverReservedSize);
        cmd.bindSamplerHeap(resMan.descMan.samplerHeap.gpuAddress, resMan.descMan.samplerHeap.size, resMan.descMan.samplerReservedSize);
        cmd.endTimer(.BotOfPipe, timeId);

        try self.recordNodes(cmd, renderNodes, resMan, shaderMan, swapMan, pushData);

        try cmd.end();
        return cmd;
    }

    fn recordTransfers(_: *CmdRecorder, cmd: *Cmd, resMan: *ResourceMan) !void {
        var resUpdater = &resMan.updater;
        const stagingBuf = resUpdater.getStagingBuffer(cmd.flightId);

        const fullTransfers = resUpdater.getFullUpdates(cmd.flightId);
        if (fullTransfers.len != 0) {
            const timeId = cmd.startTimer(.AllCmds, "Full Transfers", .Other);

            for (fullTransfers) |transfer| {
                const buffer = try resMan.getBuf(transfer.dstResId);
                cmd.copyBuffer(stagingBuf, transfer, buffer.handle);
            }
            cmd.endTimer(.BotOfPipe, timeId);
        }

        const partialTransfers = resUpdater.getSegmentUpdates(cmd.flightId);
        if (partialTransfers.len != 0) {
            const timeId = cmd.startTimer(.AllCmds, "Partial Transfers", .Other);

            for (partialTransfers) |transfer| {
                const buffer = try resMan.getBuf(transfer.dstResId);
                cmd.copyBuffer(stagingBuf, transfer, buffer.handle);
            }
            cmd.endTimer(.BotOfPipe, timeId);
        }

        // textures
        const texTransfers = resUpdater.getTexUpdates(cmd.flightId);
        if (texTransfers.len != 0) {
            const timeId = cmd.startTimer(.AllCmds, "Texture Transfers", .Other);

            for (texTransfers) |transfer| {
                const tex = try resMan.getTex(transfer.dstTexId);
                cmd.copyBufferToImage(stagingBuf, tex.img, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, transfer.width, transfer.height, transfer.srcOffset);
            }
            cmd.endTimer(.BotOfPipe, timeId);
        }

        resUpdater.resetUpdates(cmd.flightId);
    }

    fn stageTextureBarrier(self: *CmdRecorder, img: vk.VkImage, typ: vhE.TexTyp, srcState: TextureState, dstState: TextureState) !void {
        try self.imgBarriers.append(makeImageBarrier(img, typ, srcState, dstState));
    }

    fn stageMemBarrier(self: *CmdRecorder, oldStage: u64, oldAccess: u64, newStage: u64, newAccess: u64) !void {
        self.memBarrier = vk.VkMemoryBarrier2{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = oldStage,
            .srcAccessMask = oldAccess,
            .dstStageMask = newStage,
            .dstAccessMask = newAccess,
        };
    }

    fn stageBufferBarrier(self: *CmdRecorder, buf: *const Buffer, srcState: BufferState, dstState: BufferState) !void {
        try self.bufBarriers.append(makeBarrier(buf.handle, srcState, dstState));
    }

    fn recordNodes(self: *CmdRecorder, cmd: *Cmd, renderNodes: *const RenderNodeRing, resMan: *ResourceMan, shaderMan: *ShaderManager, swapMan: *SwapchainMan, pushData: []const u8) !void {
        for (0..renderNodes.length()) |nodeIndex| {
            const renderNode = renderNodes.get(@intCast(nodeIndex));
            switch (renderNode) {
                .passPrint => {},
                .compositePrint => {},
                .uiPrint => {},

                .recordTransfers => try self.recordTransfers(cmd, resMan),

                // Graph Commands
                .clearBuffer => |clearBufId| {
                    const buffer: *const Buffer = try resMan.getBuf(clearBufId);
                    cmd.fillBuffer(buffer.handle, 0, vk.VK_WHOLE_SIZE, 0);
                },
                .clearTexture => |clearTexId| {
                    const texture: *const Texture = try resMan.getTex(clearTexId);
                    switch (texture.typ) {
                        .Color16, .Color8, .Swapchain => cmd.clearColorImage(texture.img, 0.0, 0.0, 0.0, 0.0), // Maybe alpha should be 1 ??
                        .Depth32, .Stencil8 => cmd.clearDepthImage(texture.img, 0.0, 0.0),
                    }
                },

                // Profiling Commands
                .startTimer => |startTimer| {
                    try cmd.startTimerWithId(startTimer.pipeStage, startTimer.name.get(), startTimer.typ, startTimer.queryId);
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
                .memBarrier => |memBarrier| {
                    try self.stageMemBarrier(memBarrier.oldStage, memBarrier.oldAccess, memBarrier.newStage, memBarrier.newAccess);
                },
                .bufBarrier => |bufBarrier| {
                    const buf = try resMan.getBuf(bufBarrier.bufId);
                    try self.stageBufferBarrier(buf, bufBarrier.oldState, bufBarrier.newState);
                },
                .texBarrier => |texBarrier| {
                    const tex = try resMan.getTex(texBarrier.texId);
                    try self.stageTextureBarrier(tex.img, tex.typ, texBarrier.oldState, texBarrier.newState);
                },

                .swapchainTargetBarrier => |targetBarrier| {
                    const targetIndex = swapMan.getTargetIndex(targetBarrier.windowId) orelse {
                        std.debug.print("swapchainTargetBarrier: no swapchain target for window {}\n", .{targetBarrier.windowId.val()});
                        return error.NoSwapchainTarget;
                    };
                    const swapchain = swapMan.getTargetByIndex(targetIndex);
                    const targetTex = swapchain.getCurTexture();
                    try self.stageTextureBarrier(targetTex.img, targetTex.typ, targetBarrier.oldState, targetBarrier.newState);
                },
                .bakeBarriers => {
                    self.bakeBarriers(cmd, "Bake Barriers");
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

                    const bufDesc = try resMan.getBufDescriptor(push.bufId);
                    const src = std.mem.asBytes(&bufDesc)[0..push.size]; // desc is u32

                    @memcpy(self.state.pushData[push.offset..][0..push.size], src);
                    self.state.pushDataLen = @max(self.state.pushDataLen, push.size + push.offset);
                },
                .setPushDataTexDesc => |push| {
                    std.debug.assert(push.size <= 128);
                    std.debug.assert(push.offset + push.size <= 128);

                    const texDesc = try resMan.getTexDescriptor(push.texId, push.descTyp);
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
                    const tex = try resMan.getTex(dispatchImg.texId);
                    const extent = tex.extent;
                    cmd.dispatch(
                        (extent.width + dispatchImg.groupX - 1) / dispatchImg.groupX,
                        (extent.height + dispatchImg.groupY - 1) / dispatchImg.groupY,
                        (extent.depth + dispatchImg.groupZ - 1) / dispatchImg.groupZ,
                    );
                },
                .dispatchIndirect => |dispatchIndirect| {
                    const buffer = try resMan.getBuf(dispatchIndirect.indirectBufId);
                    cmd.dispatchIndirect(buffer.handle, dispatchIndirect.indirectBufOffset);
                },

                .setOutputExtentSwapchain => |output| {
                    const targetIndex = swapMan.getTargetIndex(output) orelse {
                        std.debug.print("beginRenderingSwapchain: no swapchain target for window {}\n", .{output.val()});
                        return error.NoSwapchainTarget;
                    };
                    const swapchain = swapMan.getTargetByIndex(targetIndex);
                    const targetTex = swapchain.getCurTexture();
                    if (self.state.outputWidth == null) self.state.outputWidth = targetTex.extent.width else return error.CmdStateOutputWidthAlreadySet;
                    if (self.state.outputHeight == null) self.state.outputHeight = targetTex.extent.height else return error.CmdStateOutputHeightAlreadySet;
                },
                .setOutputExtent => |output| {
                    if (output) |outputTexId| {
                        const tex = try resMan.getTex(outputTexId);
                        if (self.state.outputWidth == null) self.state.outputWidth = tex.extent.width else return error.CmdStateOutputWidthAlreadySet;
                        if (self.state.outputHeight == null) self.state.outputHeight = tex.extent.height else return error.CmdStateOutputHeightAlreadySet;
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
                    const tex = try resMan.getTex(texViewport);
                    cmd.setViewport(0, 0, @floatFromInt(tex.extent.width), @floatFromInt(tex.extent.height));
                },
                .setScissorFromTex => |texScissor| {
                    const tex = try resMan.getTex(texScissor);
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
                    const targetIndex = swapMan.getTargetIndex(swapchainAtt.windowId) orelse {
                        std.debug.print("beginRenderingSwapchain: no swapchain target for window {}\n", .{swapchainAtt.windowId.val()});
                        return error.NoSwapchainTarget;
                    };
                    const swapchain = swapMan.getTargetByIndex(targetIndex);
                    const targetTex = swapchain.getCurTexture();
                    const colorAtt = try createAttachment(targetTex.view, targetTex.typ, if (swapchainAtt.firstUse) .{ .color = rc.INITIAL_SWAPCHAIN_COLOR } else null);

                    self.state.colorAtts.append(colorAtt) catch return error.CmdStateColorAttsFull;
                },
                .setColorAtt => |setColorAtt| {
                    const tex = try resMan.getTex(setColorAtt.texId);
                    const colorAtt = try createAttachment(tex.view, tex.typ, if (setColorAtt.clear) |clear| .{ .color = clear } else null);

                    self.state.colorAtts.append(colorAtt) catch return error.CmdStateColorAttsFull;
                },
                .setDepthAtt => |depth| {
                    const tex = try resMan.getTex(depth.texId);
                    const depthAtt = try createAttachment(tex.view, tex.typ, if (depth.clear) |clear| .{ .depth = clear } else null);

                    if (self.state.depthAtt == null) self.state.depthAtt = depthAtt else return error.CmdStateDepthAttAlreadySet;
                },
                .setStencilAtt => |stencil| {
                    const tex = try resMan.getTex(stencil.texId);
                    const stencilAtt = try createAttachment(tex.view, tex.typ, if (stencil.clear) |clear| .{ .depth = clear } else null);

                    if (self.state.stencilAtt == null) self.state.stencilAtt = stencilAtt else return error.CmdStateStencilAttAlreadySet;
                },

                .setIndexBuf => |indexBuf| {
                    if (self.state.indexBuffer == null) self.state.indexBuffer = indexBuf else return error.CmdIndexBufAlreadySet;
                },
                .setVertexBuf => |vertBuf| {
                    self.state.vertexBuffers.append(vertBuf) catch return error.CmdStateVertexBuffersFull;
                },
                .setVertexAttrib => |attrib| {
                    self.state.vertexAttributes.append(attrib) catch return error.CmdStateVertexAttributesFull;
                },
                .bindIndexInput => {
                    if (self.state.indexBuffer) |indexBuffer| {
                        const buffer = try resMan.getBuf(indexBuffer.bufId);
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
                            bufHandles[i] = (try resMan.getBuf(vbUse.bufId)).handle;
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
                    const buffer = try resMan.getBuf(drawTasksOrMeshIndirect.indirectBufId);
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

    fn bakeBarriers(self: *CmdRecorder, cmd: *const Cmd, name: []const u8) void {
        const imgBarrierCount = self.imgBarriers.items.len;
        const bufBarrierCount = self.bufBarriers.items.len;
        const hasMemBarrier = self.memBarrier != null;

        if (imgBarrierCount != 0 or bufBarrierCount != 0 or hasMemBarrier) {
            if (rc.BARRIER_DEBUG) std.debug.print("BakeBarriers: {} Img, {} Buf, {} Mem {s}\n", .{ imgBarrierCount, bufBarrierCount, self.memBarrier, name });

            if (self.memBarrier) |memBarrier| {
                cmd.bakeBarriers(self.imgBarriers.items, self.bufBarriers.items, &.{memBarrier});
                self.memBarrier = null;
            } else {
                cmd.bakeBarriers(self.imgBarriers.items, self.bufBarriers.items, &.{});
            }

            self.imgBarriers.clearRetainingCapacity();
            self.bufBarriers.clearRetainingCapacity();
        } else if (rc.BARRIER_DEBUG) std.debug.print("BakeBarriers: Skipped because none are staged! ({s})\n", .{name});
    }
};

fn createAttachment(view: vk.VkImageView, typ: vhE.TexTyp, clear: ?ClearValue) !vk.VkRenderingAttachmentInfo {
    var clearValue: vk.VkClearValue = undefined;

    if (clear) |clearColor| {
        switch (clearColor) {
            .color => |color| switch (typ) {
                .Color16, .Color8, .Swapchain => clearValue = vk.VkClearValue{ .color = .{ .float32 = .{ color.R, color.G, color.B, color.A } } },
                else => return error.ColorFormatHasDepthColor,
            },
            .depth => |depthStencil| switch (typ) {
                .Depth32, .Stencil8 => clearValue = vk.VkClearValue{ .depthStencil = .{ .depth = depthStencil.depthStencil.depth, .stencil = depthStencil.depthStencil.stencil } },
                else => return error.DepthFormatHasDepthColor,
            },
        }
    }

    return vk.VkRenderingAttachmentInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = view,
        .imageLayout = vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        .loadOp = if (clear != null) vk.VK_ATTACHMENT_LOAD_OP_CLEAR else vk.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = clearValue,
    };
}

fn makeImageBarrier(img: vk.VkImage, typ: vhE.TexTyp, oldState: TextureState, newState: TextureState) vk.VkImageMemoryBarrier2 {
    const subRange = vhF.createSubresourceRange(typ.getImageAspectFlags(), 0, 1, 0, 1);

    const barrier = vk.VkImageMemoryBarrier2{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = @intFromEnum(oldState.stage),
        .srcAccessMask = @intFromEnum(oldState.access),
        .dstStageMask = @intFromEnum(newState.stage),
        .dstAccessMask = @intFromEnum(newState.access),
        .oldLayout = @intFromEnum(oldState.layout),
        .newLayout = @intFromEnum(newState.layout),
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = img,
        .subresourceRange = subRange,
    };
    return barrier;
}

pub fn makeBarrier(buf: vk.VkBuffer, oldState: BufferState, newState: BufferState) vk.VkBufferMemoryBarrier2 {
    const barrier = vk.VkBufferMemoryBarrier2{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
        .srcStageMask = @intFromEnum(oldState.stage),
        .srcAccessMask = @intFromEnum(oldState.access),
        .dstStageMask = @intFromEnum(newState.stage),
        .dstAccessMask = @intFromEnum(newState.access),
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .buffer = buf,
        .offset = 0,
        .size = vk.VK_WHOLE_SIZE, // whole Buffer
    };
    return barrier;
}
