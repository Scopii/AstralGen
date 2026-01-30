const PushConstants = @import("../types/res/PushConstants.zig").PushConstants;
const TextureBase = @import("../types/res/TextureBase.zig").TextureBase;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const TexId = @import("../types/res/Texture.zig").Texture.TexId;
const ResourceMan = @import("ResourceMan.zig").ResourceMan;
const ShaderManager = @import("ShaderMan.zig").ShaderMan;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const FrameData = @import("../../App.zig").FrameData;
const Pass = @import("../types/base/Pass.zig").Pass;
const Cmd = @import("../types/base/Cmd.zig").Cmd;
const CmdManager = @import("CmdMan.zig").CmdMan;
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const vhT = @import("../help/Types.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

pub const RenderGraph = struct {
    alloc: Allocator,
    cmdMan: CmdManager,
    pipeLayout: vk.VkPipelineLayout,
    descLayoutAddress: u64,
    imgBarriers: std.array_list.Managed(vk.VkImageMemoryBarrier2),
    bufBarriers: std.array_list.Managed(vk.VkBufferMemoryBarrier2),

    pub fn init(alloc: Allocator, context: *const Context, resMan: *const ResourceMan) !RenderGraph {
        return .{
            .alloc = alloc,
            .cmdMan = try CmdManager.init(alloc, context, rc.MAX_IN_FLIGHT),
            .pipeLayout = resMan.descMan.pipeLayout,
            .descLayoutAddress = resMan.descMan.descBuffer.gpuAddress,
            .imgBarriers = try std.array_list.Managed(vk.VkImageMemoryBarrier2).initCapacity(alloc, 30),
            .bufBarriers = try std.array_list.Managed(vk.VkBufferMemoryBarrier2).initCapacity(alloc, 30),
        };
    }

    pub fn deinit(self: *RenderGraph) void {
        self.cmdMan.deinit();
        self.imgBarriers.deinit();
        self.bufBarriers.deinit();
    }

    pub fn recordFrame(self: *RenderGraph, passes: []Pass, flightId: u8, frame: u64, frameData: FrameData, targets: []const *Swapchain, resMan: *ResourceMan, shaderMan: *ShaderManager) !*Cmd {
        var cmd = try self.cmdMan.getCmd(flightId);
        try cmd.begin(flightId, frame);

        cmd.resetQuerys();

        cmd.startQuery(.TopOfPipe, 76, "Cmd-Setup");
        cmd.bindDescriptorBuffer(self.descLayoutAddress);
        cmd.setDescriptorBufferOffset(vk.VK_PIPELINE_BIND_POINT_COMPUTE, self.pipeLayout);
        cmd.setDescriptorBufferOffset(vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeLayout);
        cmd.endQuery(.BotOfPipe, 76);

        try self.recordTransfers(cmd, resMan);
        // try self.recordIndirectResets(cmd, resMan);
        try self.recordPasses(cmd, passes, frameData, resMan, shaderMan);
        try self.recordSwapchainBlits(cmd, targets, resMan);

        try cmd.end();
        return cmd;
    }

    pub fn recordTransfers(self: *RenderGraph, cmd: *Cmd, resMan: *ResourceMan) !void {
        if (resMan.transfers.items.len == 0) return;
        cmd.startQuery(.TopOfPipe, 40, "Transfers");

        for (resMan.transfers.items) |transfer| {
            const buffer = try resMan.getBufferPtr(transfer.dstResId);
            try self.bufferBarrierIfNeeded(buffer, .{ .stage = .Transfer, .access = .TransferWrite });
            cmd.copyBuffer(resMan.stagingBuffer.handle, &transfer, buffer.handle);
        }
        resMan.resetTransfers();
        self.bakeBarriers(cmd);
        cmd.endQuery(.BotOfPipe, 40);
    }

    pub fn recordIndirectResets(self: *RenderGraph, cmd: *const Cmd, resMan: *ResourceMan) !void {
        cmd.startQuery(.TopOfPipe, 66, "Indirect-Reset");

        for (resMan.indirectBufIds.items) |id| {
            const indirectBuf = try resMan.getBufferPtr(id);
            try self.bufBarriers.append(indirectBuf.createBufferBarrier(.{ .stage = .Transfer, .access = .TransferWrite }));
        }
        self.bakeBarriers(cmd);

        for (resMan.indirectBufIds.items) |id| {
            const indirectBuf = try resMan.getBufferPtr(id);
            cmd.fillBuffer(indirectBuf.handle, 0, @sizeOf(vhT.IndirectData), 0);
        }
        cmd.endQuery(.BotOfPipe, 66);
    }

    fn imageBarrierIfNeeded(self: *RenderGraph, tex: *TextureBase, neededState: TextureBase.TextureState) !void {
        const state = tex.state;
        if (state.stage == neededState.stage and state.access == neededState.access and state.layout == neededState.layout) return;
        try self.imgBarriers.append(tex.createImageBarrier(neededState));
    }

    fn bufferBarrierIfNeeded(self: *RenderGraph, buffer: *Buffer, neededState: Buffer.BufferState) !void {
        const state = buffer.state;
        if ((state.stage == neededState.stage and state.access == neededState.access) or
            (state.access == .ShaderRead or state.access == .IndirectRead and
                neededState.access == .ShaderRead or neededState.access == .IndirectRead)) return;

        try self.bufBarriers.append(buffer.createBufferBarrier(neededState));
    }

    pub fn recordPassBarriers(self: *RenderGraph, cmd: *const Cmd, pass: Pass, resMan: *ResourceMan) !void {
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

    fn recordCompute(cmd: *const Cmd, dispatch: Pass.Dispatch, renderTexId: ?TexId, resMan: *ResourceMan) !void {
        if (renderTexId) |texId| {
            const tex = try resMan.getTexturePtr(texId);
            cmd.dispatch(
                (tex.base.extent.width + dispatch.x - 1) / dispatch.x,
                (tex.base.extent.height + dispatch.y - 1) / dispatch.y,
                (tex.base.extent.depth + dispatch.z - 1) / dispatch.z,
            );
        } else cmd.dispatch(dispatch.x, dispatch.y, dispatch.z);
    }

    pub fn recordPasses(self: *RenderGraph, cmd: *Cmd, passes: []Pass, frameData: FrameData, resMan: *ResourceMan, shaderMan: *ShaderManager) !void {
        for (passes, 0..) |pass, i| {
            cmd.startQuery(.TopOfPipe, @intCast(i), pass.name);

            switch (pass.typ) {
                .classic => |classic| cmd.setGraphicsState(classic.state),
                else => {},
            }
            const shaders = shaderMan.getShaders(pass.shaderIds)[0..pass.shaderIds.len];
            cmd.bindShaders(shaders);
            const pcs = try PushConstants.init(resMan, pass, frameData);
            cmd.setPushConstants(self.pipeLayout, vk.VK_SHADER_STAGE_ALL, 0, @sizeOf(PushConstants), &pcs);

            try self.recordPassBarriers(cmd, pass, resMan);

            switch (pass.typ) {
                .compute => |comp| try recordCompute(cmd, comp.workgroups, comp.mainTexId, resMan),
                .classic => |classic| try recordGraphics(cmd, pcs.width, pcs.height, classic, resMan),
            }
            cmd.endQuery(.BotOfPipe, @intCast(i));
        }
    }

    fn recordGraphics(cmd: *const Cmd, width: u32, height: u32, passData: Pass.ClassicPass, resMan: *ResourceMan) !void {
        if (passData.colorAtts.len > 8) return error.TooManyAttachments;

        const depthInf: ?vk.VkRenderingAttachmentInfo = if (passData.depthAtt) |depth| blk: {
            const tex = try resMan.getTexturePtr(depth.texId);
            break :blk tex.base.createAttachment(depth.clear);
        } else null;

        const stencilInf: ?vk.VkRenderingAttachmentInfo = if (passData.stencilAtt) |stencil| blk: {
            const tex = try resMan.getTexturePtr(stencil.texId);
            break :blk tex.base.createAttachment(stencil.clear);
        } else null;

        var colorInfs: [8]vk.VkRenderingAttachmentInfo = undefined;
        for (0..passData.colorAtts.len) |i| {
            const color = passData.colorAtts[i];
            const tex = try resMan.getTexturePtr(color.texId);
            colorInfs[i] = tex.base.createAttachment(color.clear);
        }

        cmd.beginRendering(width, height, colorInfs[0..passData.colorAtts.len], depthInf, stencilInf);

        switch (passData.classicTyp) {
            .taskMesh => |taskMesh| {
                if (taskMesh.indirectBuf) |indirectBuf| {
                    const buffer = try resMan.getBufferPtr(indirectBuf.id);
                    cmd.drawMeshTasksIndirect(buffer.handle, 0 + @sizeOf(vhT.IndirectData), 1, @sizeOf(vhT.IndirectData)); // * cmd.flightId
                } else {
                    cmd.drawMeshTasks(taskMesh.workgroups.x, taskMesh.workgroups.y, taskMesh.workgroups.z);
                }
            },
            .graphics => |graphics| {
                cmd.setEmptyVertexInput();
                cmd.draw(graphics.draw.vertices, graphics.draw.instances, 0, 0);
            },
        }
        cmd.endRendering();
    }

    pub fn recordSwapchainBlits(self: *RenderGraph, cmd: *Cmd, swapchains: []const *Swapchain, resMan: *ResourceMan) !void {
        cmd.startQuery(.TopOfPipe, 55, "Blits");

        for (swapchains) |swapchain| { // Render Texture and Swapchain Preperations
            const renderTex = try resMan.getTexturePtr(swapchain.renderTexId);
            try self.imageBarrierIfNeeded(&renderTex.base, .{ .stage = .Transfer, .access = .TransferRead, .layout = .TransferSrc });
            try self.imageBarrierIfNeeded(&swapchain.textures[swapchain.curIndex], .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst });
        }
        self.bakeBarriers(cmd);

        for (swapchains) |swapchain| { // Blits
            const renderTex = try resMan.getTexturePtr(swapchain.renderTexId);
            cmd.copyImageToImage(renderTex.base.img, renderTex.base.extent, swapchain.getCurTexture().img, swapchain.getExtent3D(), rc.RENDER_TEX_STRETCH);
        }
        for (swapchains) |swapchain| { // Swapchain Presentation Barriers
            try self.imageBarrierIfNeeded(swapchain.getCurTexture(), .{ .stage = .ColorAtt, .access = .None, .layout = .PresentSrc });
        }
        self.bakeBarriers(cmd);
        cmd.endQuery(.BotOfPipe, 55);
    }

    fn bakeBarriers(self: *RenderGraph, cmd: *const Cmd) void {
        if (self.imgBarriers.items.len != 0 or self.bufBarriers.items.len != 0) {
            cmd.bakeBarriers(self.imgBarriers.items, self.bufBarriers.items);
            self.imgBarriers.clearRetainingCapacity();
            self.bufBarriers.clearRetainingCapacity();
        }
    }
};
