const ComputeIndirectExec = @import("../types/pass/PassDef.zig").ComputeIndirectExec;
const AttachmentUse = @import("../types/pass/AttachmentUse.zig").AttachmentUse;
const TexId = @import("../types/res/TextureMeta.zig").TextureMeta.TexId;
const ViewportBlit = @import("../types/pass/PassDef.zig").ViewportBlit;
const TextureUse = @import("../types/pass/TextureUse.zig").TextureUse;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const RenderNode = @import("../types/pass/PassDef.zig").RenderNode;
const BufferUse = @import("../types/pass/BufferUse.zig").BufferUse;
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
const pc = @import("../../.configs/passConfig.zig");

const Cmd = @import("../types/base/Cmd.zig").Cmd;
const CmdManager = @import("CmdMan.zig").CmdMan;
const Context = @import("Context.zig").Context;
const vk = @import("../../.modules/vk.zig").c;
const vhT = @import("../help/Types.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

const EngineData = @import("../../EngineData.zig").EngineData;

pub const RenderGraph = struct {
    alloc: Allocator,
    gpi: vk.VkDevice,
    cmdMan: CmdManager,
    imgBarriers: std.array_list.Managed(vk.VkImageMemoryBarrier2),
    bufBarriers: std.array_list.Managed(vk.VkBufferMemoryBarrier2),
    useGpuProfiling: bool = rc.GPU_PROFILING,
    lastPassTyp: ?PassDef.PassExecution = null,

    pub fn init(alloc: Allocator, context: *const Context) !RenderGraph {
        return .{
            .alloc = alloc,
            .gpi = context.gpi,
            .cmdMan = try CmdManager.init(alloc, context, rc.MAX_IN_FLIGHT),
            .imgBarriers = try std.array_list.Managed(vk.VkImageMemoryBarrier2).initCapacity(alloc, 30),
            .bufBarriers = try std.array_list.Managed(vk.VkBufferMemoryBarrier2).initCapacity(alloc, 30),
        };
    }

    pub fn deinit(self: *RenderGraph) void {
        self.imgBarriers.deinit();
        self.bufBarriers.deinit();
        self.cmdMan.deinit();
    }

    pub fn toggleGpuProfiling(self: *RenderGraph) void {
        if (self.useGpuProfiling == true) self.useGpuProfiling = false else self.useGpuProfiling = true;
    }

    pub fn recordFrame(
        self: *RenderGraph,
        renderNodes: []RenderNode,
        flightId: u8,
        frame: u64,
        frameData: FrameData,
        swapMan: *SwapchainMan,
        resMan: *ResourceMan,
        shaderMan: *ShaderManager,
        meshTaskSupport: bool,
    ) !*Cmd {
        var cmd = try self.cmdMan.getCmd(flightId);
        try cmd.begin(flightId, frame);

        if (self.useGpuProfiling == true and frame % rc.GPU_QUERY_INTERVAL == 0) try cmd.enableTimeQuerys(self.gpi) else cmd.disableTimeQuerys(self.gpi);
        cmd.resetTimeQuerys();

        if (self.useGpuProfiling == true and frame % rc.GPU_QUERY_INTERVAL == 0) try cmd.enableStatsQuerys(self.gpi) else cmd.disableStatsQuerys(self.gpi);
        cmd.resetStatsQuerys();

        const timeId = cmd.startTimer(.TopOfPipe, "Descriptor Heap", .Other);
        cmd.bindDescriptorHeap(resMan.descMan.descHeap.gpuAddress, resMan.descMan.descHeap.size, resMan.descMan.driverReservedSize);
        cmd.endTimer(.BotOfPipe, timeId);

        try self.recordTransfers(cmd, resMan);
        try self.recordNodes(cmd, renderNodes, frameData, resMan, shaderMan, swapMan, meshTaskSupport);
        try self.recordPresentation(cmd, swapMan);

        try cmd.end();
        return cmd;
    }

    fn recordTransfers(self: *RenderGraph, cmd: *Cmd, resMan: *ResourceMan) !void {
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

    fn checkImageState(self: *RenderGraph, tex: *Texture, neededState: Texture.TextureState) !void {
        const state = tex.state;
        if (state.stage == neededState.stage and state.access == neededState.access and state.layout == neededState.layout) return;
        try self.imgBarriers.append(tex.createImageBarrier(neededState));
    }

    fn checkBufferState(self: *RenderGraph, buffer: *Buffer, neededState: Buffer.BufferState) !void {
        const state = buffer.state;
        if (state.stage == neededState.stage and state.access == neededState.access) return;

        const curReadOnly = state.access == .ShaderRead or
            state.access == .IndirectRead or
            state.access == .VertexAttributeRead or
            state.access == .IndexRead;

        const newReadOnly = neededState.access == .ShaderRead or
            neededState.access == .IndirectRead or
            neededState.access == .VertexAttributeRead or
            neededState.access == .IndexRead;

        if (curReadOnly and newReadOnly) return;

        try self.bufBarriers.append(buffer.createBufferBarrier(neededState));
    }

    fn recordPassBarriers(self: *RenderGraph, cmd: *const Cmd, pass: *const PassDef, resMan: *ResourceMan) !void {
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
        for (pass.vertexBuffers.constSlice()) |vbUse| {
            const buf = try resMan.get(vbUse.bufId, cmd.flightId);
            try self.checkBufferState(buf, .{ .stage = .VertexInput, .access = .VertexAttributeRead });
        }
        if (pass.indexBuffer) |ibUse| {
            const buf = try resMan.get(ibUse.bufId, cmd.flightId);
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

    fn recordComputeIndirect(cmd: *const Cmd, compIndirectExec: ComputeIndirectExec, resMan: *ResourceMan) !void {
        const buffer = try resMan.get(compIndirectExec.indirectBuf, cmd.flightId);
        cmd.dispatchIndirect(buffer.handle, compIndirectExec.indirectBufOffset);
    }

    fn recordNodes(
        self: *RenderGraph,
        cmd: *Cmd,
        renderNodes: []RenderNode,
        frameData: FrameData,
        resMan: *ResourceMan,
        shaderMan: *ShaderManager,
        swapMan: *SwapchainMan,
        meshTaskSupport: bool,
    ) !void {
        for (renderNodes) |renderNode| {
            switch (renderNode) {
                .passNode => |passNode| {
                    const specialPass: bool = switch (passNode.pass.execution) {
                        .taskOrMesh, .taskOrMeshIndirect => true,
                        .computeOnImg, .compute, .computeIndirect, .graphics => false,
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
                .uiNode => |uiNode| try self.recordUiNode(cmd, uiNode, resMan, shaderMan, swapMan),
            }
        }
    }

    fn recordUiNode(self: *RenderGraph, cmd: *Cmd, uiNode: UiNode, resMan: *ResourceMan, shaderMan: *ShaderManager, swapMan: *SwapchainMan) !void {
        const timeId = cmd.startTimer(.TopOfPipe, "ImGui Native UI", .Other);

        const targetIndex = swapMan.getTargetIndex(uiNode.windowId) orelse return;
        const swapchain = swapMan.getTargetByIndex(targetIndex);
        const targetTex = swapchain.getCurTexture();

        const pass = pc.ImGuiPass(.{
            .name = "ImGui",
            .colorAtt = swapchain.renderTexId, // Target!
            .vertexBuf = rc.imguiVertexSB.id,
            .indexBuf = rc.imguiIndexSB.id,
        });

        try self.checkImageState(targetTex, .{ .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .Attachment });

        // All other barriers driven by the PassDef — vertex buffers, index buffer, textures
        for (pass.vertexBuffers.constSlice()) |vbUse| {
            const buf = try resMan.get(vbUse.bufId, cmd.flightId);
            try self.checkBufferState(buf, .{ .stage = .VertexInput, .access = .VertexAttributeRead });
        }
        if (pass.indexBuffer) |ibUse| {
            const buf = try resMan.get(ibUse.bufId, cmd.flightId);
            try self.checkBufferState(buf, .{ .stage = .VertexInput, .access = .IndexRead });
        }
        for (uiNode.cmdLists) |cmdList| {
            for (cmdList.cmds) |drawCmd| {
                if (resMan.get(drawCmd.texId, cmd.flightId)) |tex| {
                    try self.checkImageState(tex, .{ .stage = .Fragment, .access = .ShaderRead, .layout = .General });
                } else |_| {}
            }
        }
        self.bakeBarriers(cmd, "UI Prep");

        // Setup driven by PassDef — same as recordGraphics for a vertex pass
        const colorAtt = targetTex.createAttachment(.Swapchain, false);
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

        const ImGuiPushConstants = extern struct { scale: [2]f32, translate: [2]f32, texDesc: u32 };

        const scaleX = 2.0 / uiNode.displaySize[0];
        const scaleY = 2.0 / uiNode.displaySize[1];
        const translateX = -1.0 - uiNode.displayPos[0] * scaleX;
        const translateY = -1.0 - uiNode.displayPos[1] * scaleY;
        const sw = @as(f32, @floatFromInt(swapchain.extent.width));
        const sh = @as(f32, @floatFromInt(swapchain.extent.height));

        for (uiNode.cmdLists) |cmdList| {
            for (cmdList.cmds) |drawCmd| {
                const x0 = @max(0.0, @min(drawCmd.clipRect[0] - uiNode.displayPos[0], sw));
                const y0 = @max(0.0, @min(drawCmd.clipRect[1] - uiNode.displayPos[1], sh));
                const x1 = @max(x0, @min(drawCmd.clipRect[2] - uiNode.displayPos[0], sw));
                const y1 = @max(y0, @min(drawCmd.clipRect[3] - uiNode.displayPos[1], sh));
                if (x1 - x0 <= 0 or y1 - y0 <= 0) continue;

                cmd.setScissor(x0, y0, x1 - x0, y1 - y0);

                const pushConstants = ImGuiPushConstants{
                    .scale = .{ scaleX, scaleY },
                    .translate = .{ translateX, translateY },
                    .texDesc = try resMan.getDescriptor(drawCmd.texId, cmd.flightId),
                };
                cmd.setPushData(&pushConstants, @sizeOf(@TypeOf(pushConstants)), 0);
                cmd.drawIndexed(drawCmd.elemCount, 1, drawCmd.idxOffset, drawCmd.vtxOffset, 0);
            }
        }

        cmd.endRendering();
        cmd.endTimer(.BotOfPipe, timeId);
    }

    fn recordPass(self: *RenderGraph, cmd: *Cmd, pass: *const PassDef, frameData: FrameData, resMan: *ResourceMan, shaderMan: *ShaderManager) !void {
        const timeId = cmd.startTimer(.TopOfPipe, pass.name, .Pass);
        cmd.startStatistics(pass.name);

        const shaders = shaderMan.getShaders(pass.getShaderIds());
        const shaderSlice = shaders[0..pass.getShaderIds().len];
        cmd.bindShaders(shaderSlice);
        const pushData = try PushData.init(resMan, pass.getBufUses(), pass.getTexUses(), pass.getMainTexId(), frameData, cmd.flightId);
        cmd.setPushData(&pushData, @sizeOf(PushData), 0);

        try self.recordPassBarriers(cmd, pass, resMan);

        switch (pass.execution) {
            .taskOrMesh, .taskOrMeshIndirect, .graphics => try recordGraphics(cmd, pushData.width, pushData.height, pass, resMan),
            .computeOnImg => |computeOnImg| try recordCompute(cmd, computeOnImg.workgroups, computeOnImg.mainTexId, resMan),
            .compute => |compute| try recordCompute(cmd, compute.workgroups, null, resMan),
            .computeIndirect => |computeIndirect| try recordComputeIndirect(cmd, computeIndirect, resMan),
        }
        cmd.endTimer(.BotOfPipe, timeId);
        cmd.endStatistics();
    }

    fn recordBlit(self: *RenderGraph, cmd: *Cmd, blit: ViewportBlit, resMan: *ResourceMan, swapMan: *SwapchainMan) !void {
        const timeId = cmd.startTimer(.TopOfPipe, blit.name, .Blit);

        const renderTex = try resMan.get(blit.srcTexId, cmd.flightId);

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

    fn recordGraphics(cmd: *Cmd, width: u32, height: u32, pass: *const PassDef, resMan: *ResourceMan) !void {
        const depthInf: ?vk.VkRenderingAttachmentInfo = if (pass.depthAtt) |depth| blk: {
            const texMeta = try resMan.getMeta(depth.texId);
            const tex = try resMan.get(depth.texId, cmd.flightId);
            break :blk tex.createAttachment(texMeta.texType, depth.clear);
        } else null;

        const stencilInf: ?vk.VkRenderingAttachmentInfo = if (pass.stencilAtt) |stencil| blk: {
            const texMeta = try resMan.getMeta(stencil.texId);
            const tex = try resMan.get(stencil.texId, cmd.flightId);
            break :blk tex.createAttachment(texMeta.texType, stencil.clear);
        } else null;

        var colorInfs: [8]vk.VkRenderingAttachmentInfo = undefined;
        for (pass.getColorAtts(), 0..) |colorAtt, i| {
            const texMeta = try resMan.getMeta(colorAtt.texId);
            const tex = try resMan.get(colorAtt.texId, cmd.flightId);
            colorInfs[i] = tex.createAttachment(texMeta.texType, colorAtt.clear);
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
            .compute, .computeOnImg, .computeIndirect => std.debug.print("ERROR: Compute or ComputeOnImg Pass ({s}) landed in Graphics Recording\n", .{pass.name}),
        }
        cmd.endRendering();
    }

    fn recordPresentation(self: *RenderGraph, cmd: *Cmd, swapMan: *SwapchainMan) !void {
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

    fn bakeBarriers(self: *RenderGraph, cmd: *const Cmd, name: []const u8) void {
        const imgBarrierCount = self.imgBarriers.items.len;
        const bufBarrierCount = self.bufBarriers.items.len;

        if (imgBarrierCount != 0 or bufBarrierCount != 0) {
            if (rc.BARRIER_DEBUG == true) std.debug.print("BakeBarriers: {} Img, {} Buf ({s})\n", .{ imgBarrierCount, bufBarrierCount, name });
            cmd.bakeBarriers(self.imgBarriers.items, self.bufBarriers.items);
            self.imgBarriers.clearRetainingCapacity();
            self.bufBarriers.clearRetainingCapacity();
        } else if (rc.BARRIER_DEBUG == true) std.debug.print("BakeBarriers: Skipped ({s})\n", .{name});
    }

    fn bindVertexInputFromPass(cmd: *Cmd, pass: *const PassDef, resMan: *ResourceMan, flightId: u8) !void {
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
