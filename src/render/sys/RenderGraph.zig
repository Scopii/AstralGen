const AttachmentUse = @import("../types/pass/AttachmentUse.zig").AttachmentUse;
const TexId = @import("../types/res/TextureMeta.zig").TextureMeta.TexId;
const ViewportBlit = @import("../types/pass/PassDef.zig").ViewportBlit;
const TextureUse = @import("../types/pass/TextureUse.zig").TextureUse;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const RenderNode = @import("../types/pass/PassDef.zig").RenderNode;
const BufferUse = @import("../types/pass/BufferUse.zig").BufferUse;
const PushData = @import("../types/res/PushData.zig").PushData;
const Dispatch = @import("../types/pass/PassDef.zig").Dispatch;
const SwapchainMan = @import("SwapchainMan.zig").SwapchainMan;
const PassDef = @import("../types/pass/PassDef.zig").PassDef;
const Texture = @import("../types/res/Texture.zig").Texture;
const ResourceMan = @import("ResourceMan.zig").ResourceMan;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const ShaderManager = @import("ShaderMan.zig").ShaderMan;
const rc = @import("../../.configs/renderConfig.zig");
const FrameData = @import("../../App.zig").FrameData;

const ImGuiMan = @import("ImGuiMan.zig").ImGuiMan;
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

    pub fn recordFrame(self: *RenderGraph, renderNodes: []RenderNode, flightId: u8, frame: u64, frameData: FrameData, swapMan: *SwapchainMan, resMan: *ResourceMan, shaderMan: *ShaderManager, imguiMan: *ImGuiMan, data: *const EngineData) !*Cmd {
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
        try self.recordNodes(cmd, renderNodes, frameData, resMan, shaderMan, swapMan);
        try self.recordImGui(cmd, swapMan, imguiMan, data);
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
                const buffer = try resMan.get(transfer.dstResId, transfer.dstSlot);
                try self.checkBufferState(buffer, .{ .stage = .Transfer, .access = .TransferWrite });
                cmd.copyBuffer(stagingBuf, transfer, buffer.handle);
            }
            resUpdater.resetFullUpdates(cmd.flightId);
            self.bakeBarriers(cmd, "Full Transfers");

            cmd.endTimer(.BotOfPipe, timeId);
        }

        const partialTransfers = resUpdater.getSegmentUpdates(cmd.flightId);

        if (partialTransfers.len != 0) {
            const timeId = cmd.startTimer(.TopOfPipe, "Partial Transfers", .Other);

            for (partialTransfers) |transfer| {
                const buffer = try resMan.get(transfer.dstResId, transfer.dstSlot);
                try self.checkBufferState(buffer, .{ .stage = .Transfer, .access = .TransferWrite });
                cmd.copyBuffer(stagingBuf, transfer, buffer.handle);
            }
            resUpdater.resetSegmentUpdates(cmd.flightId);
            self.bakeBarriers(cmd, "Segment Transfers");
            cmd.endTimer(.BotOfPipe, timeId);
        }
    }

    fn checkImageState(self: *RenderGraph, tex: *Texture, subRange: vk.VkImageSubresourceRange, neededState: Texture.TextureState) !void {
        const state = tex.state;
        if (state.stage == neededState.stage and state.access == neededState.access and state.layout == neededState.layout) return;
        try self.imgBarriers.append(tex.createImageBarrier(neededState, subRange));
    }

    fn checkBufferState(self: *RenderGraph, buffer: *Buffer, neededState: Buffer.BufferState) !void {
        const state = buffer.state;
        if (state.stage == neededState.stage and state.access == neededState.access) return;

        const curReadOnly = state.access == .ShaderRead or state.access == .IndirectRead;
        const newReadOnly = neededState.access == .ShaderRead or neededState.access == .IndirectRead;
        if (state.stage == neededState.stage and state.access == neededState.access) return;
        if (curReadOnly and newReadOnly) return; // read to read needs no barrier

        try self.bufBarriers.append(buffer.createBufferBarrier(neededState));
    }

    fn recordPassBarriers(
        self: *RenderGraph,
        cmd: *const Cmd,
        name: []const u8,
        bufUses: []const BufferUse,
        texUses: []const TextureUse,
        colorAtts: []const AttachmentUse,
        depthAtt: ?AttachmentUse,
        stencilAtt: ?AttachmentUse,
        resMan: *ResourceMan,
    ) !void {
        for (bufUses) |bufUse| {
            const buffer = try resMan.get(bufUse.bufId, cmd.flightId);
            try self.checkBufferState(buffer, bufUse.getNeededState());
        }
        for (texUses) |texUse| {
            const texMeta = try resMan.getMeta(texUse.texId);
            const tex = try resMan.get(texUse.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, texUse.getNeededState());
        }
        for (colorAtts) |attachment| {
            const texMeta = try resMan.getMeta(attachment.texId);
            const tex = try resMan.get(attachment.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, attachment.getNeededState());
        }
        if (depthAtt) |attachment| {
            const texMeta = try resMan.getMeta(attachment.texId);
            const tex = try resMan.get(attachment.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, attachment.getNeededState());
        }
        if (stencilAtt) |attachment| {
            const texMeta = try resMan.getMeta(attachment.texId);
            const tex = try resMan.get(attachment.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, attachment.getNeededState());
        }
        self.bakeBarriers(cmd, name);
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

    fn recordNodes(self: *RenderGraph, cmd: *Cmd, renderNodes: []RenderNode, frameData: FrameData, resMan: *ResourceMan, shaderMan: *ShaderManager, swapMan: *SwapchainMan) !void {
        for (renderNodes) |renderNode| {
            switch (renderNode) {
                .passNode => |passNode| {
                    try self.recordPass(cmd, &passNode.pass, frameData, resMan, shaderMan);
                },
                .viewportBlit => |blit| {
                    try self.recordBlit(cmd, blit, resMan, swapMan);
                },
            }
        }
    }

    fn recordPass(self: *RenderGraph, cmd: *Cmd, pass: *const PassDef, frameData: FrameData, resMan: *ResourceMan, shaderMan: *ShaderManager) !void {
        const timeId = cmd.startTimer(.TopOfPipe, pass.name, .Pass);
        cmd.startStatistics(pass.name);

        const shaders = shaderMan.getShaders(pass.getShaderIds());
        const shaderSlice = shaders[0..pass.getShaderIds().len];
        cmd.bindShaders(shaderSlice);
        const pushData = try PushData.init(resMan, pass.getBufUses(), pass.getTexUses(), pass.getMainTexId(), frameData, cmd.flightId);
        cmd.setPushData(&pushData, @sizeOf(PushData), 0);

        try self.recordPassBarriers(cmd, pass.name, pass.getBufUses(), pass.getTexUses(), pass.getColorAtts(), pass.depthAtt, pass.stencilAtt, resMan);

        switch (pass.execution) {
            .taskOrMesh, .taskOrMeshIndirect, .graphics => try recordGraphics(cmd, pushData.width, pushData.height, pass, resMan),
            .computeOnImg => |computeOnImg| try recordCompute(cmd, computeOnImg.workgroups, computeOnImg.mainTexId, resMan),
            .compute => |compute| try recordCompute(cmd, compute.workgroups, null, resMan),
        }
        cmd.endTimer(.BotOfPipe, timeId);
        cmd.endStatistics();
    }

    fn recordBlit(self: *RenderGraph, cmd: *Cmd, blit: ViewportBlit, resMan: *ResourceMan, swapMan: *SwapchainMan) !void {
        const timeId = cmd.startTimer(.TopOfPipe, blit.name, .Blit);

        const renderTexMeta = try resMan.getMeta(blit.srcTexId);
        const renderTex = try resMan.get(blit.srcTexId, cmd.flightId);

        const targetIndex = swapMan.getTargetIndex(blit.dstWindowId) orelse return;
        const swapchain = swapMan.getTargetByIndex(targetIndex);

        try self.checkImageState(renderTex, renderTexMeta.subRange, .{ .stage = .Transfer, .access = .TransferRead, .layout = .TransferSrc });
        try self.checkImageState(&swapchain.textures[swapchain.curIndex], swapchain.subRange, .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst });
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
        cmd.setViewportAndScissor(0, 0, @floatFromInt(width), @floatFromInt(height));
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
                cmd.setEmptyVertexInput();
                cmd.draw(graphics.vertices, graphics.instances, 0, 0);
            },
            .compute, .computeOnImg => std.debug.print("ERROR: Compute or ComputeOnImg Pass ({s}) landed in Graphics Recording\n", .{pass.name}),
        }
        cmd.endRendering();
    }

    fn recordImGui(self: *RenderGraph, cmd: *Cmd, swapMan: *SwapchainMan, imguiMan: *ImGuiMan, data: *const EngineData) !void {
        if (data.window.uiActive) {
            const timeId = cmd.startTimer(.TopOfPipe, "ImGui", .Other);

            const targetIndices = swapMan.getTargetsIndices();

            for (targetIndices) |index| {
                const swapchain = swapMan.getTargetByIndex(index);
                const target = swapchain.getCurTexture();
                try self.checkImageState(target, swapchain.subRange, .{ .stage = .ColorAtt, .access = .ColorAttWrite, .layout = .Attachment });
            }
            self.bakeBarriers(cmd, "ImGui Prep");

            for (targetIndices) |index| {
                const swapchain = swapMan.getTargetByIndex(index);
                const target = swapchain.getCurTexture();
                const colorAtt = target.createAttachment(.Color, false);

                cmd.beginRendering(swapchain.extent.width, swapchain.extent.height, &[_]vk.VkRenderingAttachmentInfo{colorAtt}, null, null);
                imguiMan.render(swapchain.windowId, cmd);
                cmd.endRendering();
            }
            cmd.endTimer(.BotOfPipe, timeId);
        }
    }

    fn recordPresentation(self: *RenderGraph, cmd: *Cmd, swapMan: *SwapchainMan) !void {
        const timeId = cmd.startTimer(.TopOfPipe, "Presentation", .Other);

        const targetIndices = swapMan.getTargetsIndices();
        for (targetIndices) |index| {
            const swapchain = swapMan.getTargetByIndex(index);
            const target = swapchain.getCurTexture();
            try self.checkImageState(target, swapchain.subRange, .{ .stage = .BotOfPipe, .access = .None, .layout = .PresentSrc });
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
};
