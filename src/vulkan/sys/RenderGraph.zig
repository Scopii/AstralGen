const TextureBase = @import("../types/res/TextureBase.zig").TextureBase;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const TexId = @import("../types/res/Texture.zig").Texture.TexId;
const PushData = @import("../types/res/PushData.zig").PushData;
const ResourceMan = @import("ResourceMan.zig").ResourceMan;
const ShaderManager = @import("ShaderMan.zig").ShaderMan;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const FrameData = @import("../../App.zig").FrameData;
const Pass = @import("../types/base/Pass.zig").Pass;
const Cmd = @import("../types/base/Cmd.zig").Cmd;
const CmdManager = @import("CmdMan.zig").CmdMan;
const Context = @import("Context.zig").Context;
const vhF = @import("../help/Functions.zig");
const vk = @import("../../modules/vk.zig").c;
const vhT = @import("../help/Types.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

pub const RenderGraph = struct {
    alloc: Allocator,
    gpi: vk.VkDevice,
    cmdMan: CmdManager,
    imgBarriers: std.array_list.Managed(vk.VkImageMemoryBarrier2),
    bufBarriers: std.array_list.Managed(vk.VkBufferMemoryBarrier2),

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

    pub fn recordFrame(self: *RenderGraph, passes: []Pass, flightId: u8, frame: u64, frameData: FrameData, targets: []const *Swapchain, resMan: *ResourceMan, shaderMan: *ShaderManager) !*Cmd {
        var cmd = try self.cmdMan.getCmd(flightId);
        try cmd.begin(flightId, frame);

        cmd.resetQuerys();

        cmd.startQuery(.TopOfPipe, 76, "Desc-Heap-bind");
        cmd.bindDescriptorHeap(resMan.descMan.descHeap.gpuAddress, resMan.descMan.descHeap.size, resMan.descMan.driverReservedSize);
        cmd.endQuery(.BotOfPipe, 76);

        try self.recordTransfers(cmd, resMan);
        try self.recordPasses(cmd, passes, frameData, resMan, shaderMan);
        try self.recordSwapchainBlits(cmd, targets, resMan);

        try cmd.end();
        return cmd;
    }

    pub fn recordTransfers(self: *RenderGraph, cmd: *Cmd, resMan: *ResourceMan) !void {
        if (resMan.transfers[cmd.flightId].items.len == 0) return;
        cmd.startQuery(.TopOfPipe, 40, "Transfers");

        for (resMan.transfers[cmd.flightId].items) |transfer| {
            const buffer = try resMan.getBufferPtr(transfer.dstResId);
            try self.checkBufferState(buffer, .{ .stage = .Transfer, .access = .TransferWrite });

            const copyRegion = vk.VkBufferCopy{
                .srcOffset = transfer.srcOffset,
                .dstOffset = transfer.dstOffset,
                .size = transfer.size,
            };
            vk.vkCmdCopyBuffer(cmd.handle, resMan.stagingBuffers[cmd.flightId].handle, buffer.handle, 1, &copyRegion);
        }
        resMan.resetTransfers(cmd.flightId);
        self.bakeBarriers(cmd);
        cmd.endQuery(.BotOfPipe, 40);
    }

    fn checkImageState(self: *RenderGraph, tex: *TextureBase, neededState: TextureBase.TextureState) !void {
        const state = tex.state;
        if (state.stage == neededState.stage and state.access == neededState.access and state.layout == neededState.layout) return;
        try self.imgBarriers.append(tex.createImageBarrier(neededState));
    }

    fn checkBufferState(self: *RenderGraph, buffer: *Buffer, neededState: Buffer.BufferState) !void {
        const state = buffer.state;
        if ((state.stage == neededState.stage and state.access == neededState.access) or
            (state.access == .ShaderRead or state.access == .IndirectRead and
                neededState.access == .ShaderRead or neededState.access == .IndirectRead)) return;

        try self.bufBarriers.append(buffer.createBufferBarrier(neededState));
    }

    pub fn recordPassBarriers(self: *RenderGraph, cmd: *const Cmd, pass: Pass, resMan: *ResourceMan) !void {
        for (pass.bufUses) |bufUse| {
            const buffer = try resMan.getBufferPtr(bufUse.bufId);
            try self.checkBufferState(buffer, bufUse.getNeededState());
        }
        for (pass.texUses) |texUse| {
            const tex = try resMan.getTexturePtr(texUse.texId);
            try self.checkImageState(&tex.base[cmd.flightId], texUse.getNeededState());
        }
        for (pass.getColorAtts()) |colorAtt| {
            const tex = try resMan.getTexturePtr(colorAtt.texId);
            try self.checkImageState(&tex.base[cmd.flightId], colorAtt.getNeededState());
        }
        if (pass.getDepthAtt()) |depthAtt| {
            const tex = try resMan.getTexturePtr(depthAtt.texId);
            try self.checkImageState(&tex.base[cmd.flightId], depthAtt.getNeededState());
        }
        if (pass.getStencilAtt()) |stencilAtt| {
            const tex = try resMan.getTexturePtr(stencilAtt.texId);
            try self.checkImageState(&tex.base[cmd.flightId], stencilAtt.getNeededState());
        }
        self.bakeBarriers(cmd);
    }

    fn recordCompute(cmd: *const Cmd, dispatch: Pass.Dispatch, renderTexId: ?TexId, resMan: *ResourceMan) !void {
        if (renderTexId) |texId| {
            const tex = try resMan.getTexturePtr(texId);
            cmd.dispatch(
                (tex.base[cmd.flightId].extent.width + dispatch.x - 1) / dispatch.x,
                (tex.base[cmd.flightId].extent.height + dispatch.y - 1) / dispatch.y,
                (tex.base[cmd.flightId].extent.depth + dispatch.z - 1) / dispatch.z,
            );
        } else cmd.dispatch(dispatch.x, dispatch.y, dispatch.z);
    }

    pub fn recordPasses(self: *RenderGraph, cmd: *Cmd, passes: []Pass, frameData: FrameData, resMan: *ResourceMan, shaderMan: *ShaderManager) !void {
        for (passes, 0..) |pass, i| {
            cmd.startQuery(.TopOfPipe, @intCast(i), pass.name);

            const shaders = shaderMan.getShaders(pass.shaderIds)[0..pass.shaderIds.len];
            cmd.bindShaders(shaders);

            const pushData = try PushData.init(resMan, pass, frameData, cmd.flightId);
            cmd.setPushData(&pushData, @sizeOf(PushData), 0);

            try self.recordPassBarriers(cmd, pass, resMan);

            switch (pass.typ) {
                .classic => |classic| {
                    cmd.setGraphicsState(classic.state);
                    try recordGraphics(cmd, pushData.width, pushData.height, classic, resMan);
                },
                .compute => |comp| try recordCompute(cmd, comp.workgroups, comp.mainTexId, resMan),
            }
            cmd.endQuery(.BotOfPipe, @intCast(i));
        }
    }

    fn recordGraphics(cmd: *const Cmd, width: u32, height: u32, passData: Pass.ClassicPass, resMan: *ResourceMan) !void {
        if (passData.colorAtts.len > 8) return error.TooManyAttachments;

        const depthInf: ?vk.VkRenderingAttachmentInfo = if (passData.depthAtt) |depth| blk: {
            const tex = try resMan.getTexturePtr(depth.texId);
            break :blk tex.base[cmd.flightId].createAttachment(depth.clear);
        } else null;

        const stencilInf: ?vk.VkRenderingAttachmentInfo = if (passData.stencilAtt) |stencil| blk: {
            const tex = try resMan.getTexturePtr(stencil.texId);
            break :blk tex.base[cmd.flightId].createAttachment(stencil.clear);
        } else null;

        var colorInfs: [8]vk.VkRenderingAttachmentInfo = undefined;
        for (0..passData.colorAtts.len) |i| {
            const colorAtt = passData.colorAtts[i];
            const tex = try resMan.getTexturePtr(colorAtt.texId);
            colorInfs[i] = tex.base[cmd.flightId].createAttachment(colorAtt.clear);
        }

        cmd.beginRendering(width, height, colorInfs[0..passData.colorAtts.len], depthInf, stencilInf);

        switch (passData.classicTyp) {
            .taskMesh => |taskMesh| {
                if (taskMesh.indirectBuf) |indirectBuf| {
                    const buffer = try resMan.getBufferPtr(indirectBuf.id);
                    cmd.drawMeshTasksIndirect(buffer.handle, indirectBuf.offset + @sizeOf(vhT.IndirectData) * cmd.flightId, 1, @sizeOf(vhT.IndirectData)); //  + @sizeOf(vhT.IndirectData) * cmd.flightId
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
            try self.checkImageState(&renderTex.base[cmd.flightId], .{ .stage = .Transfer, .access = .TransferRead, .layout = .TransferSrc });
            try self.checkImageState(&swapchain.textures[swapchain.curIndex], .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst });
        }
        self.bakeBarriers(cmd);

        for (swapchains) |swapchain| { // Blits + Swapchain Presentation Barriers
            const renderTex = try resMan.getTexturePtr(swapchain.renderTexId);
            cmd.copyImageToImage(renderTex.base[cmd.flightId].img, renderTex.base[cmd.flightId].extent, swapchain.getCurTexture().img, swapchain.getExtent3D(), rc.RENDER_TEX_STRETCH);
            try self.checkImageState(swapchain.getCurTexture(), .{ .stage = .ColorAtt, .access = .None, .layout = .PresentSrc });
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
