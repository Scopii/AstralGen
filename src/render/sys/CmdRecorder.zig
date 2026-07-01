const PassInstance = @import("../types/pass/PassInstance.zig").PassInstance;
const CompositeNode = @import("../types/pass/RenderNode.zig").CompositeNode;
const ViewportBlit = @import("../types/pass/RenderNode.zig").ViewportBlit;
const RenderNode = @import("../types/pass/RenderNode.zig").RenderNode;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const PushData = @import("../types/res/PushData.zig").PushData;
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

const ImGuiPass = @import("../../.assets/passes/Imgui/Imgui.zig").ImGuiPass;
const Composite = @import("../../.assets/passes/composite/Composite.zig").Composite;

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
    lastPassTyp: ?PassInstance.PassExecution = null,

    pub fn init(alloc: Allocator, context: *const Context) !CmdRecorder {
        return .{
            .alloc = alloc,
            .gpi = context.gpi,
            .cmdMan = try CmdManager.init(alloc, context, rc.MAX_IN_FLIGHT),
            .imgBarriers = try std.array_list.Managed(vk.VkImageMemoryBarrier2).initCapacity(alloc, 30),
            .bufBarriers = try std.array_list.Managed(vk.VkBufferMemoryBarrier2).initCapacity(alloc, 30),
            .imgClears = try std.array_list.Managed(TexId).initCapacity(alloc, 30),
            .bufClears = try std.array_list.Managed(BufId).initCapacity(alloc, 30),
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
        frameData: FrameData,
        swapMan: *SwapchainMan,
        resMan: *ResourceMan,
        shaderMan: *ShaderManager,
        meshTaskSupport: bool,
        uiDraws: []const UiNode.UiDraw,
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
        try self.recordNodes(
            cmd,
            renderNodes,
            frameData,
            resMan,
            shaderMan,
            swapMan,
            meshTaskSupport,
            uiDraws,
        );
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

    fn recordPassBarriers(
        self: *CmdRecorder,
        cmd: *const Cmd,
        pass: *const PassInstance,
        resMan: *ResourceMan,
    ) !void {
        for (pass.getBufUses()) |bufUse| {
            const buffer = try resMan.get(bufUse.bufId, cmd.flightId);
            try self.checkBufferState(buffer, bufUse.getNeededState());
        }
        for (pass.getTexUses()) |texUse| {
            const tex = try resMan.get(texUse.texId, cmd.flightId);
            try self.checkImageState(tex, texUse.getNeededState());
        }
        for (pass.getColorAtts()) |attachment| {
            const tex = try resMan.get(attachment.texId, cmd.flightId);
            try self.checkImageState(tex, attachment.getNeededState());
        }
        if (pass.depthAtt) |attachment| {
            const tex = try resMan.get(attachment.texId, cmd.flightId);
            try self.checkImageState(tex, attachment.getNeededState());
        }
        if (pass.stencilAtt) |attachment| {
            const tex = try resMan.get(attachment.texId, cmd.flightId);
            try self.checkImageState(tex, attachment.getNeededState());
        }
        for (pass.getVertexBufUse()) |vbUse| {
            const buf = try resMan.get(vbUse.bufId, cmd.flightId);
            try self.checkBufferState(buf, .{ .stage = .VertexInput, .access = .VertexAttributeRead });
        }
        if (pass.indexBuffer) |ibUse| {
            const buf = try resMan.get(ibUse.bufId, cmd.flightId);
            try self.checkBufferState(buf, .{ .stage = .VertexInput, .access = .IndexRead });
        }
        self.bakeBarriers(cmd, pass.getName());
    }

    fn recordCompute(cmd: *const Cmd, groupX: u32, groupY: u32, groupZ: u32, renderTexId: ?TexId, resMan: *ResourceMan) !void {
        if (renderTexId) |texId| {
            const tex = try resMan.get(texId, cmd.flightId);
            const extent = tex.extent;

            cmd.dispatch(
                (extent.width + groupX - 1) / groupX,
                (extent.height + groupY - 1) / groupY,
                (extent.depth + groupZ - 1) / groupZ,
            );
        } else cmd.dispatch(groupX, groupY, groupZ);
    }

    fn recordComputeIndirect(cmd: *const Cmd, indirectBufId: BufId, indirectBufOffset: u64, resMan: *ResourceMan) !void {
        const buffer = try resMan.get(indirectBufId, cmd.flightId);
        cmd.dispatchIndirect(buffer.handle, indirectBufOffset);
    }

    fn recordNodes(
        self: *CmdRecorder,
        cmd: *Cmd,
        renderNodes: []RenderNode,
        frameData: FrameData,
        resMan: *ResourceMan,
        shaderMan: *ShaderManager,
        swapMan: *SwapchainMan,
        meshTaskSupport: bool,
        uiDraws: []const UiNode.UiDraw,
    ) !void {
        for (renderNodes) |renderNode| {
            switch (renderNode) {
                .passNode => |passNode| {
                    const specialPass: bool = switch (passNode.pass.execution) {
                        .taskOrMesh, .taskOrMeshIndirect => true,
                        .compute, .computeIndirect, .graphics => false,
                    };
                    if (specialPass == true and meshTaskSupport == false) {
                        std.debug.print("PassTyp {s} is not supported -> skipped \n", .{@tagName(passNode.pass.execution)});
                        self.lastPassTyp = null;
                        continue;
                    }

                    try self.recordPass(cmd, &passNode.pass, frameData, resMan, shaderMan);
                    self.lastPassTyp = passNode.pass.execution;
                },
                .viewportBlit => |blit| {
                    if (self.lastPassTyp != null) {
                        try self.recordBlit(cmd, blit, resMan, swapMan);
                    } else std.debug.print("Blit for unsupported Pass Skipped!\n", .{});
                },
                .uiNode => |uiNode| try self.recordUiNode(cmd, uiNode, resMan, shaderMan, swapMan, uiDraws),
                .compositeNode => |composite| try self.recordCompositeNode(cmd, composite, resMan, shaderMan, swapMan),
                .clearBuffer => |clearBuf| try self.recordBufferClear(cmd, clearBuf, resMan),
                .clearTexture => |clearTex| try self.recordTextureClear(cmd, clearTex, resMan),
                .barrierBakeClears => try self.bakeAndExecuteClears(cmd, resMan),
            }
        }
    }

    fn recordBufferClear(self: *CmdRecorder, cmd: *Cmd, bufId: BufId, resMan: *ResourceMan) !void {
        const buffer: *Buffer = try resMan.get(bufId, cmd.flightId);
        try self.checkBufferState(buffer, .{ .stage = .Transfer, .access = .TransferWrite });
        try self.bufClears.append(bufId);
    }

    fn recordTextureClear(self: *CmdRecorder, cmd: *Cmd, texId: TexId, resMan: *ResourceMan) !void {
        const texture: *Texture = try resMan.get(texId, cmd.flightId);
        try self.checkImageState(texture, .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst });
        try self.imgClears.append(texId);
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

    fn recordCompositeNode(
        self: *CmdRecorder,
        cmd: *Cmd,
        composite: CompositeNode,
        resMan: *ResourceMan,
        shaderMan: *ShaderManager,
        swapMan: *SwapchainMan,
    ) !void {
        const timeId = cmd.startTimer(.TopOfPipe, composite.name, .Composite);

        const targetIndex = swapMan.getTargetIndex(composite.windowId) orelse return;
        const swapchain = swapMan.getTargetByIndex(targetIndex);
        const targetTex = swapchain.getCurTexture();

        const isFirstUse = targetTex.state.layout == .Undefined;

        if (composite.srcTexUnion != .texId) return error.CompositSrcTexIdIsNotHardwareId;

        const srcTex = try resMan.get(composite.srcTexUnion.texId, cmd.flightId);
        const srcDesc = try resMan.getTextureDescriptor(composite.srcTexUnion.texId, cmd.flightId, .Sampled);

        // Barriers: src to SampledRead, swapchain to ColorAttWrite
        try self.checkImageState(srcTex, .{ .stage = .Fragment, .access = .SampledRead, .layout = .General });
        try self.checkImageState(targetTex, .{ .stage = .ColorAtt, .access = .ColorAttReadWrite, .layout = .Attachment });
        self.bakeBarriers(cmd, "Composite Prep");

        // Color attachment = swapchain current image
        const colorAtt = try targetTex.createAttachment(.Swapchain, if (isFirstUse) .{ .color = rc.INITIAL_SWAPCHAIN_COLOR } else null);
        
        std.debug.print("SrcTex Extent: {}x{}, ", .{ srcTex.extent.width, srcTex.extent.height });
        std.debug.print("Composite {s}: windowId {} targetIndex {} -> swapchain {}x{} vs composite viewport {}x{}\n", .{ composite.name, composite.windowId.val(), targetIndex, swapchain.extent.width, swapchain.extent.height, composite.viewWidth, composite.viewHeight });
        
        cmd.beginRendering(swapchain.extent.width, swapchain.extent.height, &[_]vk.VkRenderingAttachmentInfo{colorAtt}, null, null);

        const compositePass = Composite(.{ .string = "Composite" });

        const shaders = shaderMan.getShaders(compositePass.getShaderIds());
        cmd.bindShaders(shaders[0..compositePass.getShaderIds().len]);
        cmd.updateRenderState(compositePass.renderState);

        // Viewport/scissor restricted to the target region
        cmd.setViewport(@floatFromInt(composite.viewOffsetX), @floatFromInt(composite.viewOffsetY), @floatFromInt(composite.viewWidth), @floatFromInt(composite.viewHeight));
        cmd.setScissor(@floatFromInt(composite.viewOffsetX), @floatFromInt(composite.viewOffsetY), @floatFromInt(composite.viewWidth), @floatFromInt(composite.viewHeight));

        // Push data
        const pushData = vhT.CompositePushData{
            .srcDesc = srcDesc,
            .samplerIndex = rc.SAMPLER_LINEAR_CLAMP_INDEX,
            .stretch = if (composite.stretch) 1 else 0,
            .opacity = composite.opacity,
            .dstWidth = composite.viewWidth,
            .dstHeight = composite.viewHeight,
        };
        cmd.setPushData(&pushData, @sizeOf(@TypeOf(pushData)), 0);

        cmd.setVertexInput(null, null);
        cmd.draw(3, 1, 0, 0);
        cmd.endRendering();
        cmd.endTimer(.BotOfPipe, timeId);
    }

    fn recordUiNode(self: *CmdRecorder, cmd: *Cmd, uiNode: UiNode, resMan: *ResourceMan, shaderMan: *ShaderManager, swapMan: *SwapchainMan, uiDraws: []const UiNode.UiDraw) !void {
        const timeId = cmd.startTimer(.TopOfPipe, uiNode.name, .Ui);

        const targetIndex = swapMan.getTargetIndex(uiNode.windowId) orelse {
            std.debug.print("RecordUI: no swapchain target for window {}\n", .{uiNode.windowId.val()});
            return;
        };
        const swapchain = swapMan.getTargetByIndex(targetIndex);
        const targetTex = swapchain.getCurTexture();

        const isFirstUse = targetTex.state.layout == .Undefined;

        if (uiNode.imguiVB != .bufId) return error.UiNodeImguiVBIsNotHardwareId;
        if (uiNode.imguiIB != .bufId) return error.UiNodeImguiVBIsNotHardwareId;

        const pass = ImGuiPass(.{
            .string = "Imgui",
            .vertexBuf = uiNode.imguiVB.bufId,
            .indexBuf = uiNode.imguiIB.bufId,
        });

        try self.checkImageState(targetTex, .{ .stage = .ColorAtt, .access = .ColorAttReadWrite, .layout = .Attachment });

        // All other barriers driven by the PassDef: vertex buffers, index buffer, textures
        for (pass.vertexBuffers.constSlice()) |vbUse| {
            const buf = try resMan.get(vbUse.bufId, cmd.flightId);
            try self.checkBufferState(buf, .{ .stage = .VertexInput, .access = .VertexAttributeRead });
        }
        if (pass.indexBuffer) |ibUse| {
            const buf = try resMan.get(ibUse.bufId, cmd.flightId);
            try self.checkBufferState(buf, .{ .stage = .VertexInput, .access = .IndexRead });
        }

        const uiDrawList = uiDraws[uiNode.firstDrawIndex..uiNode.lastDrawIndex];

        for (uiDrawList) |draw| { // Suboptimal but needed for custom Textures later
            if (draw.drawTex != .texId) return error.UiDrawTexIsNotAHardwareId;
            if (resMan.get(draw.drawTex.texId, cmd.flightId)) |tex| {
                try self.checkImageState(tex, .{ .stage = .Fragment, .access = .SampledRead, .layout = .General });
            } else |_| {}
        }

        self.bakeBarriers(cmd, "UI Prep");

        // Setup driven by PassDef same as recordGraphics for a vertex pass
        const colorAtt = try targetTex.createAttachment(.Swapchain, if (isFirstUse) .{ .color = rc.INITIAL_SWAPCHAIN_COLOR } else null);
        cmd.beginRendering(swapchain.extent.width, swapchain.extent.height, &[_]vk.VkRenderingAttachmentInfo{colorAtt}, null, null);

        const shaders = shaderMan.getShaders(pass.getShaderIds());
        cmd.bindShaders(shaders[0..pass.getShaderIds().len]);
        cmd.updateRenderState(pass.renderState);
        cmd.setViewport(0, 0, @floatFromInt(swapchain.extent.width), @floatFromInt(swapchain.extent.height));

        try bindVertexInputFromPass(cmd, &pass, resMan, cmd.flightId);

        if (pass.indexBuffer) |ibUse| {
            const idxBuf = try resMan.get(ibUse.bufId, cmd.flightId);
            cmd.bindIndexBuffer(idxBuf.handle, 0, ibUse.indexType);
        }

        const scaleX = 2.0 / uiNode.displaySize[0];
        const scaleY = 2.0 / uiNode.displaySize[1];
        const translateX = -1.0 - uiNode.displayPos[0] * scaleX;
        const translateY = -1.0 - uiNode.displayPos[1] * scaleY;
        const sw = @as(f32, @floatFromInt(swapchain.extent.width));
        const sh = @as(f32, @floatFromInt(swapchain.extent.height));

        var lastTexPassId: ?TexId = null;
        var lastTexDesc: u32 = undefined;

        for (uiDrawList) |draw| {
            const x0 = @max(0.0, @min(draw.clipRect[0] - uiNode.displayPos[0], sw));
            const y0 = @max(0.0, @min(draw.clipRect[1] - uiNode.displayPos[1], sh));
            const x1 = @max(x0, @min(draw.clipRect[2] - uiNode.displayPos[0], sw));
            const y1 = @max(y0, @min(draw.clipRect[3] - uiNode.displayPos[1], sh));
            if (x1 - x0 <= 0 or y1 - y0 <= 0) continue;

            cmd.setScissor(x0, y0, x1 - x0, y1 - y0);

            if (draw.drawTex != .texId) return error.UiDrawTexIsNoHardwareId;

            // fetch only when the id differs from the last one (null first iteration always misses)
            if (lastTexPassId == null or draw.drawTex.texId != lastTexPassId.?) {
                lastTexDesc = try resMan.getTextureDescriptor(draw.drawTex.texId, cmd.flightId, .Sampled);
                lastTexPassId = draw.drawTex.texId;
            }

            const pushConstants = vhT.ImGuiPushConstants{
                .scale = .{ scaleX, scaleY },
                .translate = .{ translateX, translateY },
                .texDesc = lastTexDesc,
            };
            cmd.setPushData(&pushConstants, @sizeOf(@TypeOf(pushConstants)), 0);
            cmd.drawIndexed(draw.elemCount, 1, draw.idxOffset, draw.vtxOffset, 0);
        }

        cmd.endRendering();
        cmd.endTimer(.BotOfPipe, timeId);
    }

    fn recordPass(
        self: *CmdRecorder,
        cmd: *Cmd,
        pass: *const PassInstance,
        frameData: FrameData,
        resMan: *ResourceMan,
        shaderMan: *ShaderManager,
    ) !void {
        const timeId = cmd.startTimer(.TopOfPipe, pass.getName(), .Pass);
        cmd.startStatistics(pass.getName());

        const shaders = shaderMan.getShaders(pass.getShaderIds());
        const shaderSlice = shaders[0..pass.getShaderIds().len];
        cmd.bindShaders(shaderSlice);

        const mainTexId: ?TexId = pass.getMainTexId();

        const pushData = try PushData.init(resMan, pass.getBufUses(), pass.getTexUses(), mainTexId, frameData, cmd.flightId);
        cmd.setPushData(&pushData, @sizeOf(PushData), 0);

        try self.recordPassBarriers(cmd, pass, resMan);

        switch (pass.execution) {
            .taskOrMesh, .taskOrMeshIndirect, .graphics => {
                try recordGraphics(cmd, pushData.width, pushData.height, pass, resMan);
            },
            .compute => |compute| {
                if (compute.outputTexDispatch == true) {
                    const outputTexId = pass.mainOutputTex orelse return error.ComputeOnImgOutputTexIsNull;
                    try recordCompute(cmd, compute.groupX, compute.groupY, compute.groupZ, outputTexId, resMan);
                } else {
                    try recordCompute(cmd, compute.groupX, compute.groupY, compute.groupZ, null, resMan);
                }
            },
            .computeIndirect => |computeIndirect| {
                try recordComputeIndirect(cmd, computeIndirect.indirectBuf, computeIndirect.indirectBufOffset, resMan);
            },
        }
        cmd.endTimer(.BotOfPipe, timeId);
        cmd.endStatistics();
    }

    fn recordBlit(
        self: *CmdRecorder,
        cmd: *Cmd,
        blit: ViewportBlit,
        resMan: *ResourceMan,
        swapMan: *SwapchainMan,
    ) !void {
        const timeId = cmd.startTimer(.TopOfPipe, blit.name, .Blit);

        if (blit.srcTexUnion != .texId) return error.BlitSrcIdIsNoHardwareTexId;
        const renderTex = try resMan.get(blit.srcTexUnion.texId, cmd.flightId);

        const targetIndex = swapMan.getTargetIndex(blit.dstWindowId) orelse return;
        const swapchain = swapMan.getTargetByIndex(targetIndex);

        try self.checkImageState(renderTex, .{ .stage = .Transfer, .access = .TransferRead, .layout = .TransferSrc });
        try self.checkImageState(&swapchain.textures[swapchain.curIndex], .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst });
        self.bakeBarriers(cmd, blit.name);

        const viewArea = vk.VkExtent3D{ .width = blit.viewWidth, .height = blit.viewHeight, .depth = 1 };
        const viewOffset = vk.VkOffset3D{ .x = blit.viewOffsetX, .y = blit.viewOffsetY, .z = 1 };
        cmd.blit(renderTex.img, renderTex.extent, swapchain.getCurTexture().img, viewArea, viewOffset, rc.RENDER_TEX_STRETCH);

        cmd.endTimer(.BotOfPipe, timeId);
    }

    fn recordGraphics(cmd: *Cmd, width: u32, height: u32, pass: *const PassInstance, resMan: *ResourceMan) !void {
        const depthInf: ?vk.VkRenderingAttachmentInfo = if (pass.depthAtt) |depth| blk: {
            const texMeta = try resMan.getMeta(depth.texId);
            const tex = try resMan.get(depth.texId, cmd.flightId);
            break :blk try tex.createAttachment(texMeta.typ, depth.clear);
        } else null;

        const stencilInf: ?vk.VkRenderingAttachmentInfo = if (pass.stencilAtt) |stencil| blk: {
            const texMeta = try resMan.getMeta(stencil.texId);
            const tex = try resMan.get(stencil.texId, cmd.flightId);
            break :blk try tex.createAttachment(texMeta.typ, stencil.clear);
        } else null;

        var colorInfs: [8]vk.VkRenderingAttachmentInfo = undefined;
        for (pass.getColorAtts(), 0..) |colorAtt, i| {
            const texMeta = try resMan.getMeta(colorAtt.texId);
            const tex = try resMan.get(colorAtt.texId, cmd.flightId);
            colorInfs[i] = try tex.createAttachment(texMeta.typ, colorAtt.clear);
        }

        cmd.updateRenderState(pass.renderState);
        cmd.setViewport(0, 0, @floatFromInt(width), @floatFromInt(height));
        cmd.setScissor(0, 0, @floatFromInt(width), @floatFromInt(height));
        cmd.beginRendering(width, height, colorInfs[0..pass.getColorAtts().len], if (depthInf) |*d| d else null, if (stencilInf) |*s| s else null);

        switch (pass.execution) {
            .taskOrMesh => |taskMesh| {
                cmd.drawMeshTasks(taskMesh.groupX, taskMesh.groupY, taskMesh.groupZ);
            },
            .taskOrMeshIndirect => |taskOrMeshIndirect| {
                const buffer = try resMan.get(taskOrMeshIndirect.indirectBuf, cmd.flightId);
                cmd.drawMeshTasksIndirect(buffer.handle, taskOrMeshIndirect.indirectBufOffset, 1, @sizeOf(vhT.IndirectData));
            },
            .graphics => |graphics| {
                try bindVertexInputFromPass(cmd, pass, resMan, cmd.flightId);

                if (pass.indexBuffer) |ibUse| {
                    const idxBuf = try resMan.get(ibUse.bufId, cmd.flightId);
                    cmd.bindIndexBuffer(idxBuf.handle, 0, ibUse.indexType);
                    cmd.drawIndexed(graphics.indexCount, 1, 0, 0, 0);
                } else {
                    cmd.draw(graphics.vertices, graphics.instances, 0, 0);
                }
            },
            .compute, .computeIndirect => std.debug.print("ERROR: Compute or ComputeOnImg Pass ({s}) landed in Graphics Recording\n", .{pass.getName()}),
        }
        cmd.endRendering();
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

    fn bindVertexInputFromPass(cmd: *Cmd, pass: *const PassInstance, resMan: *ResourceMan, flightId: u8) !void {
        if (pass.vertexBuffers.len == 0) {
            cmd.setVertexInput(null, null);
            return;
        }

        var bindingDescs: [4]vk.VkVertexInputBindingDescription2EXT = undefined;
        for (pass.vertexBuffers.constSlice(), 0..) |vbUse, i| {
            bindingDescs[i] = .{
                .sType = vk.VK_STRUCTURE_TYPE_VERTEX_INPUT_BINDING_DESCRIPTION_2_EXT,
                .binding = vbUse.binding,
                .stride = vbUse.stride,
                .inputRate = vbUse.inputRate,
                .divisor = 1,
            };
        }
        var attrDescs: [16]vk.VkVertexInputAttributeDescription2EXT = undefined;
        for (pass.vertexAttributes.constSlice(), 0..) |attr, i| {
            attrDescs[i] = .{
                .sType = vk.VK_STRUCTURE_TYPE_VERTEX_INPUT_ATTRIBUTE_DESCRIPTION_2_EXT,
                .location = attr.location,
                .binding = attr.binding,
                .format = attr.format,
                .offset = attr.offset,
            };
        }
        cmd.setVertexInput(bindingDescs[0..pass.vertexBuffers.len], attrDescs[0..pass.vertexAttributes.len]);

        var bufHandles: [4]vk.VkBuffer = undefined;
        var bufOffsets: [4]vk.VkDeviceSize = .{0} ** 4;

        for (pass.vertexBuffers.constSlice(), 0..) |vbUse, i| {
            bufHandles[i] = (try resMan.get(vbUse.bufId, flightId)).handle;
        }
        cmd.bindVertexBuffers(0, bufHandles[0..pass.vertexBuffers.len], bufOffsets[0..pass.vertexBuffers.len]);
    }
};
