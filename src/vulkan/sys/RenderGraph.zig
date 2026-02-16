
const TexId = @import("../types/res/TextureMeta.zig").TextureMeta.TexId;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const PushData = @import("../types/res/PushData.zig").PushData;
const Texture = @import("../types/res/Texture.zig").Texture;
const ResourceMan = @import("ResourceMan.zig").ResourceMan;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const ShaderManager = @import("ShaderMan.zig").ShaderMan;
const rc = @import("../../configs/renderConfig.zig");
const FrameData = @import("../../App.zig").FrameData;
const Pass = @import("../types/base/Pass.zig").Pass;
const ImGuiMan = @import("ImGuiMan.zig").ImGuiMan;
const Cmd = @import("../types/base/Cmd.zig").Cmd;
const CmdManager = @import("CmdMan.zig").CmdMan;
const Context = @import("Context.zig").Context;
const vhF = @import("../help/Functions.zig");
const vk = @import("../../modules/vk.zig").c;
const vhE = @import("../help/Enums.zig");
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

    pub fn recordFrame(
        self: *RenderGraph,
        passes: []Pass,
        flightId: u8,
        frame: u64,
        frameData: FrameData,
        targets: []const *Swapchain,
        resMan: *ResourceMan,
        shaderMan: *ShaderManager,
        imguiMan: *ImGuiMan,
    ) !*Cmd {
        var cmd = try self.cmdMan.getCmd(flightId);
        try cmd.begin(flightId, frame);

        cmd.resetQuerys();

        cmd.startQuery(.TopOfPipe, 76, "Descriptor Heap");
        cmd.bindDescriptorHeap(resMan.descMan.descHeap.gpuAddress, resMan.descMan.descHeap.size, resMan.descMan.driverReservedSize);
        cmd.endQuery(.BotOfPipe, 76);

        try self.recordTransfers(cmd, resMan);
        try self.recordPasses(cmd, passes, frameData, resMan, shaderMan);
        try self.recordSwapchainBlits(cmd, targets, resMan);
        try self.recordImGui(cmd, targets, imguiMan);

        try cmd.end();
        return cmd;
    }

    pub fn recordTransfers(self: *RenderGraph, cmd: *Cmd, resMan: *ResourceMan) !void {
        const resStorage = &resMan.resStorages[cmd.flightId];

        if (resStorage.transfers.items.len == 0) return;
        cmd.startQuery(.TopOfPipe, 40, "Transfers");

        for (resStorage.transfers.items) |transfer| {
            const buffer = try resMan.getBuf(transfer.dstResId, cmd.flightId);
            try self.checkBufferState(buffer, .{ .stage = .Transfer, .access = .TransferWrite });

            const copyRegion = vk.VkBufferCopy{
                .srcOffset = transfer.srcOffset,
                .dstOffset = transfer.dstOffset,
                .size = transfer.size,
            };
            vk.vkCmdCopyBuffer(cmd.handle, resStorage.stagingBuffer.handle, buffer.handle, 1, &copyRegion);
        }
        resMan.resetTransfers(cmd.flightId);
        self.bakeBarriers(cmd, "Transfers");
        cmd.endQuery(.BotOfPipe, 40);
    }

    fn checkImageState(self: *RenderGraph, tex: *Texture, subRange: vk.VkImageSubresourceRange, neededState: Texture.TextureState) !void {
        const state = tex.state;
        if (state.stage == neededState.stage and state.access == neededState.access and state.layout == neededState.layout) return;
        try self.imgBarriers.append(tex.createImageBarrier(neededState, subRange));
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
            const buffer = try resMan.getBuf(bufUse.bufId, cmd.flightId);
            try self.checkBufferState(buffer, bufUse.getNeededState());
        }
        for (pass.texUses) |texUse| {
            const texMeta = try resMan.getTexMeta(texUse.texId);
            const tex = try resMan.getTex(texUse.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, texUse.getNeededState());
        }
        for (pass.getColorAtts()) |colorAtt| {
            const texMeta = try resMan.getTexMeta(colorAtt.texId);
            const tex = try resMan.getTex(colorAtt.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, colorAtt.getNeededState());
        }
        if (pass.getDepthAtt()) |depthAtt| {
            const texMeta = try resMan.getTexMeta(depthAtt.texId);
            const tex = try resMan.getTex(depthAtt.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, depthAtt.getNeededState());
        }
        if (pass.getStencilAtt()) |stencilAtt| {
            const texMeta = try resMan.getTexMeta(stencilAtt.texId);
            const tex = try resMan.getTex(stencilAtt.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, stencilAtt.getNeededState());
        }
        self.bakeBarriers(cmd, pass.name);
    }

    fn recordCompute(cmd: *const Cmd, dispatch: Pass.Dispatch, renderTexId: ?TexId, resMan: *ResourceMan) !void {
        if (renderTexId) |texId| {
            const tex = try resMan.getTex(texId, cmd.flightId);
            const extent = tex.extent;

            cmd.dispatch(
                (extent.width + dispatch.x - 1) / dispatch.x,
                (extent.height + dispatch.y - 1) / dispatch.y,
                (extent.depth + dispatch.z - 1) / dispatch.z,
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
                    cmd.updateRenderState(classic.renderState);
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
            const texMeta = try resMan.getTexMeta(depth.texId);
            const tex = try resMan.getTex(depth.texId, cmd.flightId);
            break :blk tex.createAttachment(texMeta.texType, depth.clear);
        } else null;

        const stencilInf: ?vk.VkRenderingAttachmentInfo = if (passData.stencilAtt) |stencil| blk: {
            const texMeta = try resMan.getTexMeta(stencil.texId);
            const tex = try resMan.getTex(stencil.texId, cmd.flightId);
            break :blk tex.createAttachment(texMeta.texType, stencil.clear);
        } else null;

        var colorInfs: [8]vk.VkRenderingAttachmentInfo = undefined;
        for (0..passData.colorAtts.len) |i| {
            const colorAtt = passData.colorAtts[i];
            const texMeta = try resMan.getTexMeta(colorAtt.texId);
            const tex = try resMan.getTex(colorAtt.texId, cmd.flightId);
            colorInfs[i] = tex.createAttachment(texMeta.texType, colorAtt.clear);
        }

        cmd.beginRendering(width, height, colorInfs[0..passData.colorAtts.len], if (depthInf) |*d| d else null, if (stencilInf) |*s| s else null);

        switch (passData.classicTyp) {
            .taskMesh => |taskMesh| {
                if (taskMesh.indirectBuf) |indirectBuf| {
                    const buffer = try resMan.getBuf(indirectBuf.id, cmd.flightId);
                    cmd.drawMeshTasksIndirect(buffer.handle, indirectBuf.offset, 1, @sizeOf(vhT.IndirectData));
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
        cmd.startQuery(.TopOfPipe, 54, "Blits Prep");

        for (swapchains) |swapchain| { // Render Texture and Swapchain Preperations
            const renderTexMeta = try resMan.getTexMeta(swapchain.renderTexId);
            const renderTex = try resMan.getTex(swapchain.renderTexId, cmd.flightId);
            try self.checkImageState(renderTex, renderTexMeta.subRange, .{ .stage = .Transfer, .access = .TransferRead, .layout = .TransferSrc });
            try self.checkImageState(&swapchain.textures[swapchain.curIndex], swapchain.subRange, .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst });
        }
        self.bakeBarriers(cmd, "Blits Prep");
        cmd.endQuery(.BotOfPipe, 54);

        cmd.startQuery(.TopOfPipe, 55, "Blits Present");

        for (swapchains) |swapchain| { // Blits + Swapchain Presentation Barriers
            const renderTex = try resMan.getTex(swapchain.renderTexId, cmd.flightId);
            cmd.copyImageToImage(renderTex.img, renderTex.extent, swapchain.getCurTexture().img, swapchain.getExtent3D(), rc.RENDER_TEX_STRETCH);
            try self.checkImageState(swapchain.getCurTexture(), swapchain.subRange, .{ .stage = .ColorAtt, .access = .ColorAttReadWrite, .layout = .Attachment });
        }
        self.bakeBarriers(cmd, "Blits Present");
        cmd.endQuery(.BotOfPipe, 55);
    }

    pub fn recordImGui(self: *RenderGraph, cmd: *Cmd, swapchains: []const *Swapchain, imguiMan: *ImGuiMan) !void {
        cmd.startQuery(.TopOfPipe, 60, "ImGui");

        for (swapchains) |swapchain| {
            const target = swapchain.getCurTexture();
            const colorAtt = target.createAttachment(.Color, false);

            cmd.beginRendering(swapchain.extent.width, swapchain.extent.height, &[_]vk.VkRenderingAttachmentInfo{colorAtt}, null, null);
            imguiMan.render(cmd);
            cmd.endRendering();

            try self.checkImageState(target, swapchain.subRange, .{ .stage = .BotOfPipe, .access = .None, .layout = .PresentSrc });
        }
        self.bakeBarriers(cmd, "Imgui");
        cmd.endQuery(.BotOfPipe, 60);
    }

    fn bakeBarriers(self: *RenderGraph, cmd: *const Cmd, name: []const u8) void {
        const imgBarCount = self.imgBarriers.items.len;
        const bufBarCount = self.bufBarriers.items.len;

        if (imgBarCount != 0 or bufBarCount != 0) {
            if (rc.BARRIER_DEBUG == true) std.debug.print("BakeBarriers: {} Img, {} Buf ({s})\n", .{ imgBarCount, bufBarCount, name });
            cmd.bakeBarriers(self.imgBarriers.items, self.bufBarriers.items);
            self.imgBarriers.clearRetainingCapacity();
            self.bufBarriers.clearRetainingCapacity();
        } else if (rc.BARRIER_DEBUG == true) std.debug.print("BakeBarriers: Skipped ({s})\n", .{name});
    }
};
