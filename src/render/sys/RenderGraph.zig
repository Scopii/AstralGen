const TexId = @import("../types/res/TextureMeta.zig").TextureMeta.TexId;
const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const PushData = @import("../types/res/PushData.zig").PushData;
const Texture = @import("../types/res/Texture.zig").Texture;
const ResourceMan = @import("ResourceMan.zig").ResourceMan;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const ShaderManager = @import("ShaderMan.zig").ShaderMan;
const rc = @import("../../.configs/renderConfig.zig");
const FrameData = @import("../../App.zig").FrameData;
const Pass = @import("../types/base/Pass.zig").Pass;
const ImGuiMan = @import("ImGuiMan.zig").ImGuiMan;
const Cmd = @import("../types/base/Cmd.zig").Cmd;
const CmdManager = @import("CmdMan.zig").CmdMan;
const Context = @import("Context.zig").Context;
const vk = @import("../../.modules/vk.zig").c;
const vhT = @import("../help/Types.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

const Window = @import("../../window/Window.zig").Window;
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

    pub fn recordFrame(self: *RenderGraph, passes: []Pass, flightId: u8, frame: u64, frameData: FrameData, targets: []const *Swapchain, resMan: *ResourceMan, shaderMan: *ShaderManager, imguiMan: *ImGuiMan, windows: []const Window, data: *const EngineData) !*Cmd {
        var cmd = try self.cmdMan.getCmd(flightId);
        try cmd.begin(flightId, frame);

        if (self.useGpuProfiling == true and frame % rc.GPU_QUERY_INTERVAL == 0) try cmd.enableTimeQuerys(self.gpi) else cmd.disableTimeQuerys(self.gpi);
        cmd.resetTimeQuerys();

        if (self.useGpuProfiling == true and frame % rc.GPU_QUERY_INTERVAL == 0) try cmd.enableStatsQuerys(self.gpi) else cmd.disableStatsQuerys(self.gpi);
        cmd.resetStatsQuerys();

        cmd.startTimeQuery(.TopOfPipe, 76, "Descriptor Heap");
        cmd.bindDescriptorHeap(resMan.descMan.descHeap.gpuAddress, resMan.descMan.descHeap.size, resMan.descMan.driverReservedSize);
        cmd.endTimeQuery(.BotOfPipe, 76);

        try self.recordTransfers(cmd, resMan);
        try self.recordPasses(cmd, passes, frameData, resMan, shaderMan);
        try self.recordSwapchainBlits(cmd, targets, resMan, windows, data);
        try self.recordImGui(cmd, targets, imguiMan);

        try cmd.end();
        return cmd;
    }

    fn recordTransfers(self: *RenderGraph, cmd: *Cmd, resMan: *ResourceMan) !void {
        var resUpdater = &resMan.updater;
        const stagingBuf = resUpdater.getStagingBuffer(cmd.flightId);

        const fullTransfers = resUpdater.getFullUpdates(cmd.flightId);

        if (fullTransfers.len != 0) {
            cmd.startTimeQuery(.TopOfPipe, 40, "Full Transfers");

            for (fullTransfers) |transfer| {
                const buffer = try resMan.get(transfer.dstResId, transfer.dstSlot);
                try self.checkBufferState(buffer, .{ .stage = .Transfer, .access = .TransferWrite });
                cmd.copyBuffer(stagingBuf, transfer, buffer.handle);
            }
            resUpdater.resetFullUpdates(cmd.flightId);
            self.bakeBarriers(cmd, "Full Transfers");
            cmd.endTimeQuery(.BotOfPipe, 40);
        }

        const partialTransfers = resUpdater.getSegmentUpdates(cmd.flightId);

        if (partialTransfers.len != 0) {
            cmd.startTimeQuery(.TopOfPipe, 41, "Partial Transfers");

            for (partialTransfers) |transfer| {
                const buffer = try resMan.get(transfer.dstResId, transfer.dstSlot);
                try self.checkBufferState(buffer, .{ .stage = .Transfer, .access = .TransferWrite });
                cmd.copyBuffer(stagingBuf, transfer, buffer.handle);
            }
            resUpdater.resetSegmentUpdates(cmd.flightId);
            self.bakeBarriers(cmd, "Segment Transfers");
            cmd.endTimeQuery(.BotOfPipe, 41);
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

    fn recordPassBarriers(self: *RenderGraph, cmd: *const Cmd, pass: Pass, resMan: *ResourceMan) !void {
        for (pass.getBufUses()) |bufUse| {
            const buffer = try resMan.get(bufUse.bufId, cmd.flightId);
            try self.checkBufferState(buffer, bufUse.getNeededState());
        }
        for (pass.getTexUses()) |texUse| {
            const texMeta = try resMan.getMeta(texUse.texId);
            const tex = try resMan.get(texUse.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, texUse.getNeededState());
        }
        for (pass.getColorAtts()) |colorAtt| {
            const texMeta = try resMan.getMeta(colorAtt.texId);
            const tex = try resMan.get(colorAtt.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, colorAtt.getNeededState());
        }
        if (pass.depthAtt) |depthAtt| {
            const texMeta = try resMan.getMeta(depthAtt.texId);
            const tex = try resMan.get(depthAtt.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, depthAtt.getNeededState());
        }
        if (pass.stencilAtt) |stencilAtt| {
            const texMeta = try resMan.getMeta(stencilAtt.texId);
            const tex = try resMan.get(stencilAtt.texId, cmd.flightId);
            try self.checkImageState(tex, texMeta.subRange, stencilAtt.getNeededState());
        }
        self.bakeBarriers(cmd, pass.name);
    }

    fn recordCompute(cmd: *const Cmd, dispatch: Pass.Dispatch, renderTexId: ?TexId, resMan: *ResourceMan) !void {
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

    fn recordPasses(self: *RenderGraph, cmd: *Cmd, passes: []Pass, frameData: FrameData, resMan: *ResourceMan, shaderMan: *ShaderManager) !void {
        for (passes, 0..) |pass, i| {
            cmd.startTimeQuery(.TopOfPipe, @intCast(i), pass.name);
            cmd.beginStatsQuery(@intCast(i), pass.name);

            const shaders = shaderMan.getShaders(pass.getShaderIds())[0..pass.shaderCount];
            cmd.bindShaders(shaders);

            const pushData = try PushData.init(resMan, pass, frameData, cmd.flightId);
            cmd.setPushData(&pushData, @sizeOf(PushData), 0);

            try self.recordPassBarriers(cmd, pass, resMan);

            switch (pass.execution) {
                .taskOrMesh, .taskOrMeshIndirect, .graphics => {
                    cmd.updateRenderState(pass.renderState);
                    try recordGraphics(cmd, pushData.width, pushData.height, pass, resMan);
                },
                .computeOnImg => |computeOnImg| try recordCompute(cmd, computeOnImg.workgroups, computeOnImg.mainTexId, resMan),
                .compute => |compute| try recordCompute(cmd, compute.workgroups, null, resMan),
            }
            cmd.endTimeQuery(.BotOfPipe, @intCast(i));
            cmd.endStatsQuery(@intCast(i));
        }
    }

    fn recordGraphics(cmd: *const Cmd, width: u32, height: u32, pass: Pass, resMan: *ResourceMan) !void {
        if (pass.colorAttCount > 8) return error.TooManyAttachments;

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
        for (0..pass.getColorAtts().len) |i| {
            const colorAtt = pass.colorAtts[i];
            const texMeta = try resMan.getMeta(colorAtt.texId);
            const tex = try resMan.get(colorAtt.texId, cmd.flightId);
            colorInfs[i] = tex.createAttachment(texMeta.texType, colorAtt.clear);
        }

        cmd.setViewportAndScissor(0, 0, @floatFromInt(width), @floatFromInt(height));
        cmd.beginRendering(width, height, colorInfs[0..pass.colorAttCount], if (depthInf) |*d| d else null, if (stencilInf) |*s| s else null);

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
            else => return error.ComputePassLandedInGraphicsRecording,
        }
        cmd.endRendering();
    }

    fn recordSwapchainBlits(self: *RenderGraph, cmd: *Cmd, swapchains: []const *Swapchain, resMan: *ResourceMan, windows: []const Window, data: *const EngineData) !void {
        cmd.startTimeQuery(.TopOfPipe, 54, "Blits Prep");

        for (swapchains) |swapchain| { // Render Texture and Swapchain Preperations
            for (windows) |window| {
                if (window.id.val != swapchain.windowId) continue; // only if swapchain belongs to window

                for (window.viewIds) |viewId| {
                    if (viewId) |id| {
                        const viewport = data.viewport.viewports.getByKey(id.val);
                        const renderTexMeta = try resMan.getMeta(viewport.sourceTexId);
                        const renderTex = try resMan.get(viewport.sourceTexId, cmd.flightId);

                        try self.checkImageState(renderTex, renderTexMeta.subRange, .{ .stage = .Transfer, .access = .TransferRead, .layout = .TransferSrc });
                        try self.checkImageState(&swapchain.textures[swapchain.curIndex], swapchain.subRange, .{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst });
                    }
                }
            }
        }
        self.bakeBarriers(cmd, "Blits Prep");
        cmd.endTimeQuery(.BotOfPipe, 54);

        cmd.startTimeQuery(.TopOfPipe, 55, "Blits Present");

        for (swapchains) |swapchain| { // Blits + Swapchain Presentation Barriers
            for (windows) |window| {
                if (window.id.val != swapchain.windowId) continue; // only if swapchain belongs to window

                for (window.viewIds) |viewId| {
                    if (viewId) |id| {
                        const viewport = data.viewport.viewports.getByKey(id.val);
                        const renderTex = try resMan.get(viewport.sourceTexId, cmd.flightId);
                        const extent = swapchain.getExtent2D();
                        const width: f32 = @as(f32, @floatFromInt(extent.width)) * viewport.areaWidth;
                        const height: f32 = @as(f32, @floatFromInt(extent.height)) * viewport.areaHeight;
                        const viewArea = vk.VkExtent3D{ .width = @intFromFloat(width), .height = @intFromFloat(height), .depth = 1 };

                        const areaX: f32 = @as(f32, @floatFromInt(extent.width)) * viewport.areaX;
                        const areaY: f32 = @as(f32, @floatFromInt(extent.height)) * viewport.areaY;
                        const viewOffset = vk.VkOffset3D{ .x = @intFromFloat(areaX), .y = @intFromFloat(areaY), .z = 1 };

                        cmd.copyImageToImage(renderTex.img, renderTex.extent, swapchain.getCurTexture().img, viewArea, viewOffset, rc.RENDER_TEX_STRETCH);
                        try self.checkImageState(swapchain.getCurTexture(), swapchain.subRange, .{ .stage = .ColorAtt, .access = .ColorAttReadWrite, .layout = .Attachment });
                    }
                }
            }
        }
        self.bakeBarriers(cmd, "Blits Present");
        cmd.endTimeQuery(.BotOfPipe, 55);
    }

    fn recordImGui(self: *RenderGraph, cmd: *Cmd, swapchains: []const *Swapchain, imguiMan: *ImGuiMan) !void {
        cmd.startTimeQuery(.TopOfPipe, 60, "ImGui");

        for (swapchains) |swapchain| {
            const target = swapchain.getCurTexture();
            const colorAtt = target.createAttachment(.Color, false);

            cmd.beginRendering(swapchain.extent.width, swapchain.extent.height, &[_]vk.VkRenderingAttachmentInfo{colorAtt}, null, null);
            imguiMan.render(swapchain.windowId, cmd);
            cmd.endRendering();

            try self.checkImageState(target, swapchain.subRange, .{ .stage = .BotOfPipe, .access = .None, .layout = .PresentSrc });
        }
        self.bakeBarriers(cmd, "Imgui");
        cmd.endTimeQuery(.BotOfPipe, 60);
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
