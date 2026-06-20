const CompositeNode = @import("../types/pass/PassDef.zig").CompositeNode;
const TexId = @import("../types/res/TextureMeta.zig").TextureMeta.TexId;
const ViewportBlit = @import("../types/pass/PassDef.zig").ViewportBlit;
const BufId = @import("../types/res/BufferMeta.zig").BufferMeta.BufId;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const RenderNode = @import("../types/pass/PassDef.zig").RenderNode;
const ShaderId = @import("../../shader/ShaderSys.zig").ShaderId;
const PushData = @import("../types/res/PushData.zig").PushData;
const Dispatch = @import("../types/pass/PassDef.zig").Dispatch;
const SwapchainMan = @import("SwapchainMan.zig").SwapchainMan;
const PassDef = @import("../types/pass/PassDef.zig").PassDef;
const Texture = @import("../types/res/Texture.zig").Texture;
const ResourceMan = @import("ResourceMan.zig").ResourceMan;
const UiNode = @import("../types/pass/PassDef.zig").UiNode;
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

const TextureAssignments = @import("../../frameBuild/6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData.TextureAssignments;
const BufferAssignments = @import("../../frameBuild/6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData.BufferAssignments;
const TextureEnum = @import("../../frameBuild/enums.zig").TextureEnum;
const BufferEnum = @import("../../frameBuild/enums.zig").BufferEnum;

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
    lastPassTyp: ?PassDef.PassExecution = null,

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
        bufAssigns: *const BufferAssignments,
        texAssigns: *const TextureAssignments,
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
        try self.recordNodes(cmd, renderNodes, frameData, resMan, shaderMan, swapMan, meshTaskSupport, bufAssigns, texAssigns);
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
        pass: *const PassDef,
        resMan: *ResourceMan,
        bufAssigns: *const BufferAssignments,
        texAssigns: *const TextureAssignments,
    ) !void {
        for (pass.getBufUses()) |bufUse| {
            const bufId = try resolveBuffer(bufUse.bufLink.in, bufAssigns);
            const buffer = try resMan.get(bufId, cmd.flightId);
            try self.checkBufferState(buffer, bufUse.getNeededState());
        }
        for (pass.getTexUses()) |texUse| {
            const texId = try resolveTexture(texUse.texLink.in, texAssigns);
            const tex = try resMan.get(texId, cmd.flightId);
            try self.checkImageState(tex, texUse.getNeededState());
        }
        for (pass.getColorAtts()) |attachment| {
            const texId = try resolveTexture(attachment.texLink.in, texAssigns);
            const tex = try resMan.get(texId, cmd.flightId);
            try self.checkImageState(tex, attachment.getNeededState());
        }
        if (pass.depthAtt) |attachment| {
            const texId = try resolveTexture(attachment.texLink.in, texAssigns);
            const tex = try resMan.get(texId, cmd.flightId);
            try self.checkImageState(tex, attachment.getNeededState());
        }
        if (pass.stencilAtt) |attachment| {
            const texId = try resolveTexture(attachment.texLink.in, texAssigns);
            const tex = try resMan.get(texId, cmd.flightId);
            try self.checkImageState(tex, attachment.getNeededState());
        }
        for (pass.getVertexBufUse()) |vbUse| {
            const bufId = try resolveBuffer(vbUse.bufInput, bufAssigns);
            const buf = try resMan.get(bufId, cmd.flightId);
            try self.checkBufferState(buf, .{ .stage = .VertexInput, .access = .VertexAttributeRead });
        }
        if (pass.indexBuffer) |ibUse| {
            const bufId = try resolveBuffer(ibUse.bufInput, bufAssigns);
            const buf = try resMan.get(bufId, cmd.flightId);
            try self.checkBufferState(buf, .{ .stage = .VertexInput, .access = .IndexRead });
        }
        self.bakeBarriers(cmd, pass.name);
    }

    fn recordCompute(cmd: *const Cmd, dispatch: Dispatch, renderTexId: ?TexId, resMan: *ResourceMan) !void {
        if (renderTexId) |texId| {
            const tex = try resMan.get(texId, cmd.flightId);
            const extent = tex.extent;

            cmd.dispatch(
                (extent.width + dispatch.x - 1) / dispatch.x,
                (extent.height + dispatch.y - 1) / dispatch.y,
                (extent.depth + dispatch.z - 1) / dispatch.z,
            );
        } else cmd.dispatch(dispatch.x, dispatch.y, dispatch.z);
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
        bufAssigns: *const BufferAssignments,
        texAssigns: *const TextureAssignments,
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

                    try self.recordPass(cmd, &passNode.pass, frameData, resMan, shaderMan, bufAssigns, texAssigns);
                    self.lastPassTyp = passNode.pass.execution;
                },
                .viewportBlit => |blit| {
                    if (self.lastPassTyp != null) {
                        try self.recordBlit(cmd, blit, resMan, swapMan, texAssigns);
                    } else std.debug.print("Blit for unsupported Pass Skipped!\n", .{});
                },
                .uiNode => |uiNode| try self.recordUiNode(cmd, uiNode, resMan, shaderMan, swapMan, bufAssigns, texAssigns),
                .compositeNode => |composite| try self.recordCompositeNode(cmd, composite, resMan, shaderMan, swapMan, texAssigns),
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
        texAssigns: *const TextureAssignments,
    ) !void {
        const timeId = cmd.startTimer(.TopOfPipe, composite.name, .Composite);

        const targetIndex = swapMan.getTargetIndex(composite.windowId) orelse return;
        const swapchain = swapMan.getTargetByIndex(targetIndex);
        const targetTex = swapchain.getCurTexture();

        const isFirstUse = targetTex.state.layout == .Undefined;

        const texEnum = composite.srcTexEnum orelse return error.CompositeHasNoSrcTexId;
        const texId = try resolveTexture(texEnum, texAssigns);
        const srcTex = try resMan.get(texId, cmd.flightId);
        const srcDesc = try resMan.getTextureDescriptor(texId, cmd.flightId, .Sampled);

        // Barriers: src to SampledRead, swapchain to ColorAttWrite
        try self.checkImageState(srcTex, .{ .stage = .Fragment, .access = .SampledRead, .layout = .General });
        try self.checkImageState(targetTex, .{ .stage = .ColorAtt, .access = .ColorAttReadWrite, .layout = .Attachment });
        self.bakeBarriers(cmd, "Composite Prep");

        // Color attachment = swapchain current image
        const colorAtt = try targetTex.createAttachment(.Swapchain, if (isFirstUse) .{ .color = rc.INITIAL_SWAPCHAIN_COLOR } else null);
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

    fn recordUiNode(
        self: *CmdRecorder,
        cmd: *Cmd,
        uiNode: UiNode,
        resMan: *ResourceMan,
        shaderMan: *ShaderManager,
        swapMan: *SwapchainMan,
        bufAssigns: *const BufferAssignments,
        texAssigns: *const TextureAssignments,
    ) !void {
        const timeId = cmd.startTimer(.TopOfPipe, uiNode.name, .Ui);

        const targetIndex = swapMan.getTargetIndex(uiNode.windowId) orelse {
            std.debug.print("RecordUI: no swapchain target for window {}\n", .{uiNode.windowId.val});
            return;
        };
        const swapchain = swapMan.getTargetByIndex(targetIndex);
        const targetTex = swapchain.getCurTexture();

        const isFirstUse = targetTex.state.layout == .Undefined;

        const pass = ImGuiPass(.{
            .string = "Imgui",
            .vertexBuf = .ImguiVB,
            .indexBuf = .ImguiIB,
        });

        try self.checkImageState(targetTex, .{ .stage = .ColorAtt, .access = .ColorAttReadWrite, .layout = .Attachment });

        // All other barriers driven by the PassDef: vertex buffers, index buffer, textures
        for (pass.vertexBuffers.constSlice()) |vbUse| {
            const bufId = try resolveBuffer(vbUse.bufInput, bufAssigns);
            const buf = try resMan.get(bufId, cmd.flightId);
            try self.checkBufferState(buf, .{ .stage = .VertexInput, .access = .VertexAttributeRead });
        }
        if (pass.indexBuffer) |ibUse| {
            const bufId = try resolveBuffer(ibUse.bufInput, bufAssigns);
            const buf = try resMan.get(bufId, cmd.flightId);
            try self.checkBufferState(buf, .{ .stage = .VertexInput, .access = .IndexRead });
        }
        for (uiNode.drawList) |draw| { // Suboptimal but needed for custom Textures later
            const texId = try resolveTexture(draw.texEnum, texAssigns);
            if (resMan.get(texId, cmd.flightId)) |tex| {
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

        try bindVertexInputFromPass(cmd, &pass, resMan, cmd.flightId, bufAssigns);

        if (pass.indexBuffer) |ibUse| {
            const indexBufId = try resolveBuffer(ibUse.bufInput, bufAssigns);
            const idxBuf = try resMan.get(indexBufId, cmd.flightId);
            cmd.bindIndexBuffer(idxBuf.handle, 0, ibUse.indexType);
        }

        const scaleX = 2.0 / uiNode.displaySize[0];
        const scaleY = 2.0 / uiNode.displaySize[1];
        const translateX = -1.0 - uiNode.displayPos[0] * scaleX;
        const translateY = -1.0 - uiNode.displayPos[1] * scaleY;
        const sw = @as(f32, @floatFromInt(swapchain.extent.width));
        const sh = @as(f32, @floatFromInt(swapchain.extent.height));

        var lastTexEnum: ?TextureEnum = null;
        var lastTexDesc: u32 = undefined;

        for (uiNode.drawList) |draw| {
            const x0 = @max(0.0, @min(draw.clipRect[0] - uiNode.displayPos[0], sw));
            const y0 = @max(0.0, @min(draw.clipRect[1] - uiNode.displayPos[1], sh));
            const x1 = @max(x0, @min(draw.clipRect[2] - uiNode.displayPos[0], sw));
            const y1 = @max(y0, @min(draw.clipRect[3] - uiNode.displayPos[1], sh));
            if (x1 - x0 <= 0 or y1 - y0 <= 0) continue;

            cmd.setScissor(x0, y0, x1 - x0, y1 - y0);

            // fetch only when the id differs from the last one (null first iteration always misses)
            if (lastTexEnum == null or draw.texEnum != lastTexEnum.?) {
                const texId = try resolveTexture(draw.texEnum, texAssigns);
                lastTexDesc = try resMan.getTextureDescriptor(texId, cmd.flightId, .Sampled);
                lastTexEnum = draw.texEnum;
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

    fn resolveTexture(texEnum: TextureEnum, texAssigns: *const TextureAssignments) !TexId {
        if (texAssigns.isKeyUsed(@intFromEnum(texEnum)) == true) return texAssigns.getByKey(@intFromEnum(texEnum)) else {
            std.debug.print("Error: Texture {s} not assigned\n", .{@tagName(texEnum)});
            return error.TextureNotAssigned;
        }
    }

    fn resolveBuffer(bufEnum: BufferEnum, bufAssigns: *const BufferAssignments) !BufId {
        if (bufAssigns.isKeyUsed(@intFromEnum(bufEnum)) == true) return bufAssigns.getByKey(@intFromEnum(bufEnum)) else {
            std.debug.print("Error: Buffer {s} not assigned\n", .{@tagName(bufEnum)});
            return error.BufferNotAssigned;
        }
    }

    fn recordPass(
        self: *CmdRecorder,
        cmd: *Cmd,
        pass: *const PassDef,
        frameData: FrameData,
        resMan: *ResourceMan,
        shaderMan: *ShaderManager,
        bufAssigns: *const BufferAssignments,
        texAssigns: *const TextureAssignments,
    ) !void {
        const timeId = cmd.startTimer(.TopOfPipe, pass.name, .Pass);
        cmd.startStatistics(pass.name);

        const shaders = shaderMan.getShaders(pass.getShaderIds());
        const shaderSlice = shaders[0..pass.getShaderIds().len];
        cmd.bindShaders(shaderSlice);

        var mainTexId: ?TexId = undefined;

        if (pass.getMainTexId()) |mainTexEnum| {
            mainTexId = try resolveTexture(mainTexEnum, texAssigns);
        } else mainTexId = null;

        const pushData = try PushData.init(resMan, pass.getBufUses(), pass.getTexUses(), mainTexId, frameData, cmd.flightId, bufAssigns, texAssigns);
        cmd.setPushData(&pushData, @sizeOf(PushData), 0);

        try self.recordPassBarriers(cmd, pass, resMan, bufAssigns, texAssigns);

        switch (pass.execution) {
            .taskOrMesh, .taskOrMeshIndirect, .graphics => {
                try recordGraphics(cmd, pushData.width, pushData.height, pass, resMan, bufAssigns, texAssigns);
            },
            .compute => |compute| {
                if (compute.outputTexDispatch == true) {
                    const outputTex = pass.mainOutputTex orelse return error.ComputeOnImgOutputTexIsNull;
                    const compImgId = try resolveTexture(outputTex, texAssigns);
                    try recordCompute(cmd, compute.workgroups, compImgId, resMan);
                } else {
                    try recordCompute(cmd, compute.workgroups, null, resMan);
                }
            },
            .computeIndirect => |computeIndirect| {
                const indirectBufId = try resolveBuffer(computeIndirect.indirectBuf, bufAssigns);
                try recordComputeIndirect(cmd, indirectBufId, computeIndirect.indirectBufOffset, resMan);
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
        texAssigns: *const TextureAssignments,
    ) !void {
        const timeId = cmd.startTimer(.TopOfPipe, blit.name, .Blit);

        const texEnum = blit.srcTexEnum orelse return error.BlitHasNoSrcTexId;
        const texId = try resolveTexture(texEnum, texAssigns);
        const renderTex = try resMan.get(texId, cmd.flightId);

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

    fn recordGraphics(
        cmd: *Cmd,
        width: u32,
        height: u32,
        pass: *const PassDef,
        resMan: *ResourceMan,
        bufAssigns: *const BufferAssignments,
        texAssigns: *const TextureAssignments,
    ) !void {
        const depthInf: ?vk.VkRenderingAttachmentInfo = if (pass.depthAtt) |depth| blk: {
            const texId = try resolveTexture(depth.texLink.in, texAssigns);
            const texMeta = try resMan.getMeta(texId);
            const tex = try resMan.get(texId, cmd.flightId);
            break :blk try tex.createAttachment(texMeta.typ, depth.clear);
        } else null;

        const stencilInf: ?vk.VkRenderingAttachmentInfo = if (pass.stencilAtt) |stencil| blk: {
            const texId = try resolveTexture(stencil.texLink.in, texAssigns);
            const texMeta = try resMan.getMeta(texId);
            const tex = try resMan.get(texId, cmd.flightId);
            break :blk try tex.createAttachment(texMeta.typ, stencil.clear);
        } else null;

        var colorInfs: [8]vk.VkRenderingAttachmentInfo = undefined;
        for (pass.getColorAtts(), 0..) |colorAtt, i| {
            const texId = try resolveTexture(colorAtt.texLink.in, texAssigns);
            const texMeta = try resMan.getMeta(texId);
            const tex = try resMan.get(texId, cmd.flightId);
            colorInfs[i] = try tex.createAttachment(texMeta.typ, colorAtt.clear);
        }

        cmd.updateRenderState(pass.renderState);
        cmd.setViewport(0, 0, @floatFromInt(width), @floatFromInt(height));
        cmd.setScissor(0, 0, @floatFromInt(width), @floatFromInt(height));
        cmd.beginRendering(width, height, colorInfs[0..pass.getColorAtts().len], if (depthInf) |*d| d else null, if (stencilInf) |*s| s else null);

        switch (pass.execution) {
            .taskOrMesh => |taskMesh| {
                cmd.drawMeshTasks(taskMesh.workgroups.x, taskMesh.workgroups.y, taskMesh.workgroups.z);
            },
            .taskOrMeshIndirect => |taskOrMeshIndirect| {
                const indirectBufId = try resolveBuffer(taskOrMeshIndirect.indirectBuf, bufAssigns);
                const buffer = try resMan.get(indirectBufId, cmd.flightId);
                cmd.drawMeshTasksIndirect(buffer.handle, taskOrMeshIndirect.indirectBufOffset, 1, @sizeOf(vhT.IndirectData));
            },
            .graphics => |graphics| {
                try bindVertexInputFromPass(cmd, pass, resMan, cmd.flightId, bufAssigns);

                if (pass.indexBuffer) |ibUse| {
                    const indexBufId = try resolveBuffer(ibUse.bufInput, bufAssigns);
                    const idxBuf = try resMan.get(indexBufId, cmd.flightId);
                    cmd.bindIndexBuffer(idxBuf.handle, 0, ibUse.indexType);
                    cmd.drawIndexed(graphics.indexCount, 1, 0, 0, 0);
                } else {
                    cmd.draw(graphics.vertices, graphics.instances, 0, 0);
                }
            },
            .compute, .computeIndirect => std.debug.print("ERROR: Compute or ComputeOnImg Pass ({s}) landed in Graphics Recording\n", .{pass.name}),
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

    fn bindVertexInputFromPass(
        cmd: *Cmd,
        pass: *const PassDef,
        resMan: *ResourceMan,
        flightId: u8,
        bufAssigns: *const BufferAssignments,
    ) !void {
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
            const vertexBufId = try resolveBuffer(vbUse.bufInput, bufAssigns);
            bufHandles[i] = (try resMan.get(vertexBufId, flightId)).handle;
        }
        cmd.bindVertexBuffers(0, bufHandles[0..pass.vertexBuffers.len], bufOffsets[0..pass.vertexBuffers.len]);
    }
};
