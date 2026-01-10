const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const rc = @import("../configs/renderConfig.zig");
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const Context = @import("Context.zig").Context;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const ShaderManager = @import("ShaderManager.zig").ShaderManager;
const CmdManager = @import("CmdManager.zig").CmdManager;
const PushConstants = @import("resources/PushConstants.zig").PushConstants;
const Swapchain = @import("Swapchain.zig").Swapchain;
const Command = @import("Command.zig").Command;
const vh = @import("Helpers.zig");
const FrameData = @import("../App.zig").FrameData;
const Pass = @import("Pass.zig").Pass;
const Attachment = @import("Pass.zig").Attachment;
const TextureBase = @import("resources/TextureBase.zig").TextureBase;
const TexId = @import("resources/Texture.zig").Texture.TexId;
const Buffer = @import("resources/Buffer.zig").Buffer;
const ResourceSlot = @import("resources/PushConstants.zig").ResourceSlot;


pub const RenderGraph = struct {
    alloc: Allocator,
    cmdMan: CmdManager,
    pipeLayout: vk.VkPipelineLayout,
    descLayoutAddress: u64,
    tempImgBarriers: std.array_list.Managed(vk.VkImageMemoryBarrier2),
    tempBufBarriers: std.array_list.Managed(vk.VkBufferMemoryBarrier2),

    pub fn init(alloc: Allocator, context: *const Context, resMan: *const ResourceManager) !RenderGraph {
        return .{
            .alloc = alloc,
            .cmdMan = try CmdManager.init(alloc, context, rc.MAX_IN_FLIGHT),
            .pipeLayout = resMan.descMan.pipeLayout,
            .descLayoutAddress = resMan.descMan.descBuffer.gpuAddress,
            .tempImgBarriers = try std.array_list.Managed(vk.VkImageMemoryBarrier2).initCapacity(alloc, 30),
            .tempBufBarriers = try std.array_list.Managed(vk.VkBufferMemoryBarrier2).initCapacity(alloc, 30),
        };
    }

    pub fn deinit(self: *RenderGraph) void {
        self.cmdMan.deinit();
        self.tempImgBarriers.deinit();
        self.tempBufBarriers.deinit();
    }

    pub fn recordFrame(self: *RenderGraph, flightId: u8, resMan: *ResourceManager, frameData: FrameData, targets: []const *Swapchain, passes: []Pass, shaderMan: *ShaderManager) !Command {
        const cmd = try self.cmdMan.getCmd(flightId);
        try cmd.begin();

        cmd.bindDescriptorBuffer(self.descLayoutAddress);
        cmd.setDescriptorBufferOffset(vk.VK_PIPELINE_BIND_POINT_COMPUTE, self.pipeLayout);
        cmd.setDescriptorBufferOffset(vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeLayout);
        cmd.setGraphicsState(.{});

        for (resMan.indirectBufIds.items) |id| {
            const indirectBuf = try resMan.getBufferPtr(id);
            cmd.fillBuffer(indirectBuf.handle, 0, 16, 0);
        }

        try self.recordTransfers(&cmd, resMan);

        for (passes) |pass| {
            const shaders = shaderMan.getShaders(pass.shaderIds)[0..pass.shaderIds.len];
            cmd.bindShaders(shaders);
            try self.recordPass(&cmd, pass, frameData, resMan);
        }

        try self.recordSwapchainBlits(&cmd, targets, resMan);

        try cmd.end();
        return cmd;
    }

    pub fn recordTransfers(self: *RenderGraph, cmd: *const Command, resMan: *ResourceManager) !void {
        if (resMan.pendingTransfers.items.len == 0) return;

        for (resMan.pendingTransfers.items) |transfer| {
            const buffer = try resMan.getBufferPtr(transfer.dstResId);
            try self.bufferBarrierIfNeeded(buffer, .{ .stage = .Transfer, .access = .TransferWrite});
            cmd.copyBuffer(resMan.stagingBuffer.handle, &transfer, buffer.handle);
        }
        resMan.resetTransfers();
        self.bakeBarriers(cmd);
    }

    fn imageBarrierIfNeeded(self: *RenderGraph, tex: *TextureBase, neededState: TextureBase.TextureState) !void {
        const state = tex.state;
        if (state.stage == neededState.stage and state.access == neededState.access and state.layout == neededState.layout) return;
        try self.tempImgBarriers.append(tex.createImageBarrier(neededState));
    }

    fn bufferBarrierIfNeeded(self: *RenderGraph, buffer: *Buffer, neededState: Buffer.BufferState) !void {
        const state = buffer.state;
        if (state.stage == neededState.stage and state.access == neededState.access) return;
        try self.tempBufBarriers.append(buffer.createBufferBarrier(neededState));
    }

    pub fn recordPassBarriers(self: *RenderGraph, cmd: *const Command, pass: Pass, resMan: *ResourceManager) !void {
        for (pass.bufUses) |bufUse| {
            const buffer = try resMan.getBufferPtr(bufUse.bufId);
            try self.bufferBarrierIfNeeded(buffer, bufUse.getNeededState());
        }

        for (pass.texUses) |texUse| {
            const tex = try resMan.getTexturePtr(texUse.texId);
            try self.imageBarrierIfNeeded(&tex.base, texUse.getNeededState());
        }

        for (pass.getColorAtts()) |colorAtt| {
            const tex = try resMan.getTexturePtr(colorAtt.texId);
            try self.imageBarrierIfNeeded(&tex.base, colorAtt.getNeededState());
        }

        if (pass.getDepthAtt()) |depthAtt| {
            const tex = try resMan.getTexturePtr(depthAtt.texId);
            try self.imageBarrierIfNeeded(&tex.base, depthAtt.getNeededState());
        }

        if (pass.getStencilAtt()) |stencilAtt| {
            const tex = try resMan.getTexturePtr(stencilAtt.texId);
            try self.imageBarrierIfNeeded(&tex.base, stencilAtt.getNeededState());
        }

        self.bakeBarriers(cmd);
    }

    fn recordCompute(cmd: *const Command, dispatch: Pass.Dispatch, renderTexId: ?TexId, resMan: *ResourceManager) !void {
        if (renderTexId) |imgId| {
            const tex = try resMan.getTexturePtr(imgId);
            cmd.dispatch(
                (tex.base.extent.width + dispatch.x - 1) / dispatch.x,
                (tex.base.extent.height + dispatch.y - 1) / dispatch.y,
                (tex.base.extent.depth + dispatch.z - 1) / dispatch.z,
            );
        } else cmd.dispatch(dispatch.x, dispatch.y, dispatch.z);
    }

    pub fn recordPass(self: *RenderGraph, cmd: *const Command, pass: Pass, frameData: FrameData, resMan: *ResourceManager) !void {
        const pcs = try resMan.createPushConstants(pass, frameData);
        cmd.setPushConstants(self.pipeLayout, vk.VK_SHADER_STAGE_ALL, 0, @sizeOf(PushConstants), &pcs);

        try self.recordPassBarriers(cmd, pass, resMan);

        switch (pass.typ) {
            .compute => |comp| try recordCompute(cmd, comp.workgroups, null, resMan),
            .computeOnTex => |compOnImg| try recordCompute(cmd, compOnImg.workgroups, compOnImg.mainTexId, resMan),
            .graphics => |graphics| try recordGraphics(cmd, graphics.colorAtts, graphics.depthAtt, graphics.stencilAtt, pcs.width, pcs.height, pass, resMan),
            .taskOrMesh => |taskMesh| try recordGraphics(cmd, taskMesh.colorAtts, taskMesh.depthAtt, taskMesh.stencilAtt, pcs.width, pcs.height, pass, resMan),
            .taskOrMeshIndirect => |indirect| try recordGraphics(cmd, indirect.colorAtts, indirect.depthAtt, indirect.stencilAtt, pcs.width, pcs.height, pass, resMan),
        }
    }

    fn recordGraphics(
        cmd: *const Command,
        colorAtts: []const Attachment,
        depthAtt: ?Attachment,
        stencilAtt: ?Attachment,
        width: u32,
        height: u32,
        pass: Pass,
        resMan: *ResourceManager,
    ) !void {
        if (colorAtts.len > 8) return error.TooManyAttachments;

        const depthInf: ?vk.VkRenderingAttachmentInfo = if (depthAtt) |depth| blk: {
            const tex = try resMan.getTexturePtr(depth.texId);
            break :blk tex.base.createAttachment(depth.clear);
        } else null;

        const stencilInf: ?vk.VkRenderingAttachmentInfo = if (stencilAtt) |stencil| blk: {
            const tex = try resMan.getTexturePtr(stencil.texId);
            break :blk tex.base.createAttachment(stencil.clear);
        } else null;

        var colorInfs: [8]vk.VkRenderingAttachmentInfo = undefined;
        for (0..colorAtts.len) |i| {
            const color = colorAtts[i];
            const tex = try resMan.getTexturePtr(color.texId);
            colorInfs[i] = tex.base.createAttachment(color.clear);
        }

        cmd.beginRendering(width, height, colorInfs[0..colorAtts.len], depthInf, stencilInf);

        switch (pass.typ) {
            .compute, .computeOnTex => return error.ComputeLandedInGraphicsPass,
            .taskOrMesh => |taskOrMesh| cmd.drawMeshTasks(taskOrMesh.workgroups.x, taskOrMesh.workgroups.y, taskOrMesh.workgroups.z),
            .taskOrMeshIndirect => |tmIndirect| {
                const buffer = try resMan.getBufferPtr(tmIndirect.indirectBuf.id);
                cmd.drawMeshTasksIndirect(buffer.handle, 0, 1, 16); // 16 bytes 4x u32
            },
            .graphics => |graphics| {
                cmd.setEmptyVertexInput();
                cmd.draw(graphics.draw.vertices, graphics.draw.instances, 0, 0);
            },
        }
        cmd.endRendering();
    }

    pub fn recordSwapchainBlits(self: *RenderGraph, cmd: *const Command, swapchains: []const *Swapchain, resMan: *ResourceManager) !void {
        // Render Image and Swapchain Preperations
        for (swapchains) |swapchain| {
            const renderTex = try resMan.getTexturePtr(swapchain.renderTexId);
            try self.imageBarrierIfNeeded(&renderTex.base, .{ .stage = .Transfer, .access = .TransferRead, .layout = .TransferSrc });
            try self.imageBarrierIfNeeded(&swapchain.textures[swapchain.curIndex], .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst });
        }
        self.bakeBarriers(cmd);
        // Blits
        for (swapchains) |swapchain| {
            const renderTex = try resMan.getTexturePtr(swapchain.renderTexId);
            cmd.copyImageToImage(renderTex.base.img, renderTex.base.extent, swapchain.getCurTexture().img, swapchain.getExtent3D(), rc.RENDER_TEX_STRETCH);
        }
        // Swapchain Presentation Barriers
        for (swapchains) |swapchain| {
            try self.imageBarrierIfNeeded(swapchain.getCurTexture(), .{ .stage = .BotOfPipe, .access = .None, .layout = .PresentSrc });
        }
        self.bakeBarriers(cmd);
    }

    fn bakeBarriers(self: *RenderGraph, cmd: *const Command) void {
        if (self.tempImgBarriers.items.len != 0 or self.tempBufBarriers.items.len != 0) {
            cmd.bakeBarriers(self.tempImgBarriers.items, self.tempBufBarriers.items);
            self.tempImgBarriers.clearRetainingCapacity();
            self.tempBufBarriers.clearRetainingCapacity();
        }
    }
};
