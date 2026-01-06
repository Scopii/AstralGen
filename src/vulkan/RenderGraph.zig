const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const rc = @import("../configs/renderConfig.zig");
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const Context = @import("Context.zig").Context;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const ShaderManager = @import("ShaderManager.zig").ShaderManager;
const CmdManager = @import("CmdManager.zig").CmdManager;
const PushConstants = @import("resources/Resource.zig").PushConstants;
const SwapchainManager = @import("SwapchainManager.zig");
const Command = @import("Command.zig").Command;
const vh = @import("Helpers.zig");
const RendererData = @import("../App.zig").RendererData;
const Pass = @import("Pass.zig").Pass;
const Attachment = @import("Pass.zig").Attachment;
const Texture = @import("resources/Texture.zig").Texture;
const Buffer = @import("resources/Buffer.zig").Buffer;

pub const ResourceState = struct {
    stage: vh.PipeStage = .TopOfPipe,
    access: vh.PipeAccess = .None,
    layout: vh.ImageLayout = .Undefined,
};

pub const RenderGraph = struct {
    alloc: Allocator,
    cmdMan: CmdManager,
    pipeLayout: vk.VkPipelineLayout,
    tempImgBarriers: std.array_list.Managed(vk.VkImageMemoryBarrier2),
    tempBufBarriers: std.array_list.Managed(vk.VkBufferMemoryBarrier2),

    pub fn init(alloc: Allocator, resMan: *const ResourceManager, context: *const Context) !RenderGraph {
        return .{
            .alloc = alloc,
            .cmdMan = try CmdManager.init(alloc, context, rc.MAX_IN_FLIGHT, resMan),
            .pipeLayout = resMan.descMan.pipeLayout,
            .tempImgBarriers = try std.array_list.Managed(vk.VkImageMemoryBarrier2).initCapacity(alloc, 30),
            .tempBufBarriers = try std.array_list.Managed(vk.VkBufferMemoryBarrier2).initCapacity(alloc, 30),
        };
    }

    pub fn deinit(self: *RenderGraph) void {
        self.cmdMan.deinit();
        self.tempImgBarriers.deinit();
        self.tempBufBarriers.deinit();
    }

    pub fn recordFrame(
        self: *RenderGraph,
        frameInFlight: u8,
        resMan: *ResourceManager,
        rendererData: RendererData,
        targets: []const u32,
        swapchainMap: *SwapchainManager.SwapchainMap,
        passes: []Pass,
        shaderMan: *ShaderManager,
    ) !Command {
        const cmd = try self.cmdMan.getAndBeginCommand(frameInFlight);
        cmd.setGraphicsState();
        try self.recordTransfers(&cmd, resMan);

        for (passes) |pass| {
            const shaders = shaderMan.getShaders(pass.shaderIds)[0..pass.shaderIds.len];
            try self.recordPass(&cmd, pass, rendererData, shaders, resMan);
        }

        try self.recordSwapchainBlits(&cmd, targets, swapchainMap, resMan);
        try cmd.endRecording();

        return cmd;
    }

    pub fn recordTransfers(self: *RenderGraph, cmd: *const Command, resMan: *ResourceManager) !void {
        if (resMan.pendingTransfers.items.len == 0) return;

        for (resMan.pendingTransfers.items) |transfer| {
            const buffer = try resMan.getBufferPtr(transfer.dstResId);
            try self.bufferBarrierIfNeeded(buffer.state, .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst }, buffer);
            cmd.copyBuffer(resMan.stagingBuffer.handle, &transfer, buffer.handle); // MAYBE POINTER DEREFERNCE?
        }
        resMan.resetTransfers();
        self.bakeBarriers(cmd);
    }

    fn imageBarrierIfNeeded(self: *RenderGraph, state: ResourceState, neededState: ResourceState, tex: *Texture) !void {
        if (state.stage == neededState.stage and state.access == neededState.access and state.layout == neededState.layout) return;
        try self.tempImgBarriers.append(tex.base.createImageBarrier(neededState));
    }

    fn bufferBarrierIfNeeded(self: *RenderGraph, state: ResourceState, neededState: ResourceState, buffer: *Buffer) !void {
        if (state.stage == neededState.stage and state.access == neededState.access) return;
        try self.tempBufBarriers.append(buffer.createBufferBarrier(neededState));
    }

    pub fn recordPassBarriers(self: *RenderGraph, cmd: *const Command, pass: Pass, resMan: *ResourceManager) !void {
        for (pass.shaderBuffers) |shaderUse| {
            const buffer = try resMan.getBufferPtr(shaderUse.id);
            try self.bufferBarrierIfNeeded(buffer.state, shaderUse.getNeededState(), buffer);
        }

        for (pass.usageBuffers) |resUse| {
            const buffer = try resMan.getBufferPtr(resUse.id);
            try self.bufferBarrierIfNeeded(buffer.state, resUse.getNeededState(), buffer);
        }

        for (pass.shaderTextures) |shaderUse| {
            const tex = try resMan.getTexturePtr(shaderUse.id);
            try self.imageBarrierIfNeeded(tex.base.state, shaderUse.getNeededState(), tex);
        }

        for (pass.useageTextures) |resUse| {
            const tex = try resMan.getTexturePtr(resUse.id);
            try self.imageBarrierIfNeeded(tex.base.state, resUse.getNeededState(), tex);
        }

        for (pass.getColorAtts()) |colorAtt| {
            const tex = try resMan.getTexturePtr(colorAtt.id);
            try self.imageBarrierIfNeeded(tex.base.state, colorAtt.getNeededState(), tex);
        }

        if (pass.getDepthAtt()) |depthAtt| {
            const tex = try resMan.getTexturePtr(depthAtt.id);
            try self.imageBarrierIfNeeded(tex.base.state, depthAtt.getNeededState(), tex);
        }

        if (pass.getStencilAtt()) |stencilAtt| {
            const tex = try resMan.getTexturePtr(stencilAtt.id);
            try self.imageBarrierIfNeeded(tex.base.state, stencilAtt.getNeededState(), tex);
        }

        self.bakeBarriers(cmd);
    }

    fn recordCompute(cmd: *const Command, dispatch: Pass.Dispatch, renderTexId: ?u32, resMan: *ResourceManager) !void {
        if (renderTexId) |imgId| {
            const tex = try resMan.getTexturePtr(imgId);
            cmd.dispatch(
                (tex.base.extent.width + dispatch.x - 1) / dispatch.x,
                (tex.base.extent.height + dispatch.y - 1) / dispatch.y,
                (tex.base.extent.depth + dispatch.z - 1) / dispatch.z,
            );
        } else cmd.dispatch(dispatch.x, dispatch.y, dispatch.z);
    }

    pub fn recordPass(self: *RenderGraph, cmd: *const Command, pass: Pass, rendererData: RendererData, validShaders: []const ShaderObject, resMan: *ResourceManager) !void {
        try self.recordPassBarriers(cmd, pass, resMan);

        var pcs = PushConstants{ .runTime = rendererData.runTime, .deltaTime = rendererData.deltaTime };
        // if (pass.shaderUsages.len > pcs.resourceSlots.len) return error.TooManyShaderSlotsInPass;

        // Assign Shader Slots
        for (0..pass.shaderBuffers.len) |i| {
            const shaderSlot = pass.shaderBuffers[i];
            const buffer = try resMan.getBufferPtr(shaderSlot.id);
            pcs.resourceSlots[i] = buffer.getResourceSlot();
        }

        for (0..pass.shaderTextures.len) |i| {
            const shaderSlot = pass.shaderTextures[i];
            const images = try resMan.getTexturePtr(shaderSlot.id);
            pcs.resourceSlots[i + pass.shaderBuffers.len] = images.getResourceSlot();
        }

        const mainTex = switch (pass.passType) {
            .compute => null,
            .computeOnTex => |compOnImage| try resMan.getTexturePtr(compOnImage.mainTexId),
            .graphics => |graphics| try resMan.getTexturePtr(graphics.mainTexId),
            .taskOrMesh => |taskOrMesh| try resMan.getTexturePtr(taskOrMesh.mainTexId),
        };

        if (mainTex) |tex| {
            pcs.width = tex.base.extent.width;
            pcs.height = tex.base.extent.height;
        }

        cmd.setPushConstants(self.pipeLayout, vk.VK_SHADER_STAGE_ALL, 0, @sizeOf(PushConstants), &pcs);
        cmd.bindShaders(validShaders);

        switch (pass.passType) {
            .compute => |comp| try recordCompute(cmd, comp.workgroups, null, resMan),
            .computeOnTex => |compOnImage| try recordCompute(cmd, compOnImage.workgroups, compOnImage.mainTexId, resMan),
            .graphics => |graphics| try recordGraphics(cmd, graphics.colorAtts, graphics.depthAtt, graphics.stencilAtt, pcs.width, pcs.height, pass, resMan),
            .taskOrMesh => |taskOrMesh| try recordGraphics(cmd, taskOrMesh.colorAtts, taskOrMesh.depthAtt, taskOrMesh.stencilAtt, pcs.width, pcs.height, pass, resMan),
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
            const tex = try resMan.getTexturePtr(depth.id);
            break :blk tex.base.createAttachment(depth.clear);
        } else null;

        const stencilInf: ?vk.VkRenderingAttachmentInfo = if (stencilAtt) |stencil| blk: {
            const tex = try resMan.getTexturePtr(stencil.id);
            break :blk tex.base.createAttachment(stencil.clear);
        } else null;

        var colorInfs: [8]vk.VkRenderingAttachmentInfo = undefined;
        for (0..colorAtts.len) |i| {
            const color = colorAtts[i];
            const tex = try resMan.getTexturePtr(color.id);
            colorInfs[i] = tex.base.createAttachment(color.clear);
        }

        cmd.beginRendering(width, height, colorInfs[0..colorAtts.len], depthInf, stencilInf);

        switch (pass.passType) {
            .compute, .computeOnTex => return error.ComputeLandedInGraphicsPass,
            .taskOrMesh => |taskOrMesh| cmd.drawMeshTasks(taskOrMesh.workgroups.x, taskOrMesh.workgroups.y, taskOrMesh.workgroups.z),
            .graphics => |graphics| {
                cmd.setEmptyVertexInput();
                cmd.draw(graphics.draw.vertices, graphics.draw.instances, 0, 0);
            },
        }
        cmd.endRendering();
    }

    pub fn recordSwapchainBlits(self: *RenderGraph, cmd: *const Command, targets: []const u32, swapchainMap: *SwapchainManager.SwapchainMap, resMan: *ResourceManager) !void {
        const swapchainMidState = ResourceState{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst };
        // Render Image and Swapchain Preperations
        for (targets) |index| {
            const swapchain = swapchainMap.getPtrAtIndex(index);
            const renderTex = try resMan.getTexturePtr(swapchain.renderTexId);
            try self.imageBarrierIfNeeded(renderTex.base.state, .{ .stage = .Transfer, .access = .TransferRead, .layout = .TransferSrc }, renderTex);
            const presentTex = &swapchain.textures[swapchain.curIndex];
            try self.tempImgBarriers.append(presentTex.createImageBarrier(swapchainMidState));
        }
        self.bakeBarriers(cmd);

        // Blits
        for (targets) |index| {
            const swapchain = swapchainMap.getPtrAtIndex(index);
            const extent = vk.VkExtent3D{ .height = swapchain.extent.height, .width = swapchain.extent.width, .depth = 1 };
            const renderTex = try resMan.getTexturePtr(swapchain.renderTexId);
            cmd.copyImageToImage(renderTex.base.img, renderTex.base.extent, swapchain.textures[swapchain.curIndex].img, extent, rc.RENDER_IMG_STRETCH);
        }

        // Swapchain Presentation Barriers
        for (targets) |index| {
            const swapchain = swapchainMap.getPtrAtIndex(index);
            const presentTex = &swapchain.textures[swapchain.curIndex];
            try self.tempImgBarriers.append(presentTex.createImageBarrier(.{ .stage = .BotOfPipe, .access = .None, .layout = .PresentSrc }));
        }
        self.bakeBarriers(cmd);
    }

    fn bakeBarriers(self: *RenderGraph, cmd: *const Command) void {
        cmd.bakeBarriers(self.tempImgBarriers.items, self.tempBufBarriers.items);
        self.tempImgBarriers.clearRetainingCapacity();
        self.tempBufBarriers.clearRetainingCapacity();
    }
};
