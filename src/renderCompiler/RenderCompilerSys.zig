const TaskOrMeshIndirectExec = @import("../render/types/pass/PassDefinition.zig").TaskOrMeshIndirectExec;
const ComputeIndirectExec = @import("../render/types/pass/PassDefinition.zig").ComputeIndirectExec;
const RenderAssignerData = @import("../renderAssigner/RenderAssignerData.zig").RenderAssignerData;
const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const VertexIndexedExec = @import("../render/types/pass/PassDefinition.zig").VertexIndexedExec;
const VertexBufferFill = @import("../render/types/pass/VertexBufferUse.zig").VertexBufferFill;
const VertexBufferUse = @import("../render/types/pass/VertexBufferUse.zig").VertexBufferUse;
const VertexAttribute = @import("../render/types/pass/VertexAttribute.zig").VertexAttribute;
const IndexBufferFill = @import("../render/types/pass/IndexBufferUse.zig").IndexBufferFill;
const RenderStateUnion = @import("../render/types/pass/RenderState.zig").RenderStateUnion;
const TaskOrMeshExec = @import("../render/types/pass/PassDefinition.zig").TaskOrMeshExec;
const IndexBufferUse = @import("../render/types/pass/IndexBufferUse.zig").IndexBufferUse;
const AttachmentFill = @import("../render/types/pass/AttachmentUse.zig").AttachmentFill;
const RenderGraphData = @import("../renderGraph/RenderGraphData.zig").RenderGraphData;
const CompositeFill = @import("../render/types/pass/RenderNode.zig").CompositeFill;
const CompositeNode = @import("../render/types/pass/RenderNode.zig").CompositeNode;
const VertexExec = @import("../render/types/pass/PassDefinition.zig").VertexExec;
const BarrierState = @import("../render/types/pass/RenderNode.zig").BarrierState;
const RenderCompilerData = @import("RenderCompilerData.zig").RenderCompilerData;
const ClearColor = @import("../render/types/pass/AttachmentUse.zig").ClearColor;
const ClearDepth = @import("../render/types/pass/AttachmentUse.zig").ClearDepth;
const RenderState = @import("../render/types/pass/RenderState.zig").RenderState;
const BarrierMask = @import("../render/types/pass/RenderNode.zig").BarrierMask;
const TextureFill = @import("../render/types/pass/TextureUse.zig").TextureFill;
const TextureState = @import("../render/types/res/Texture.zig").TextureState;
const RenderNode = @import("../render/types/pass/RenderNode.zig").RenderNode;
const BufferFill = @import("../render/types/pass/BufferUse.zig").BufferFill;
const QueryTyp = @import("../render/types/base/Cmd.zig").QueryPair.QueryTyp;
const WindowData = @import("../window/WindowData.zig").WindowData;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const WindowId = @import("../.configs/idConfig.zig").WindowId;
const ShaderId = @import("../.configs/idConfig.zig").ShaderId;
const InputData = @import("../input/InputData.zig").InputData;
const PassId = @import("../.configs/idConfig.zig").PassId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const TexId = @import("../.configs/idConfig.zig").TexId;
const sc = @import("../.configs/shaderConfig.zig");
const rc = @import("../.configs/renderConfig.zig");
const UiData = @import("../ui/UiData.zig").UiData;
const vhT = @import("../render/help/Types.zig");
const vhE = @import("../render/help/Enums.zig");
const vk = @import("../.modules/vk.zig").c;
const std = @import("std");

pub const RenderCompilerSys = struct {
    pub fn compileIR(
        self: *RenderCompilerData,
        assigner: *const RenderAssignerData,
        renderGraph: *const RenderGraphData,
        registry: *const RenderRegistryData,
        uiData: *const UiData,
        windowData: *const WindowData,
        inputData: *const InputData,
        runTime: f32,
        deltaTime: f32,
    ) !void {
        self.swapchainStates.clear();
        self.renderedSwapchains.clear();
        self.renderNodes.clear();
        self.pushData.clear();
        self.usedQueries = 0;

        for (renderGraph.sorter.sortedRenderIR.constSlice()) |IR| {
            switch (IR) {
                .updateResourceStates => try updateResourceStates(self, assigner),

                .syncPoint => try bakeBarriers(self),

                .compositeIR => |*compositeIR| try fillCompositePassHardwareIdCmds(self, assigner, registry, compositeIR),

                .passIR => |passIR| try fillPassHardwareIdCmds(self, assigner, registry, passIR, runTime, deltaTime),

                .buildUi => try fillUiPassHardwareIdCmds(self, assigner, registry, uiData, windowData),

                .present => try present(self),

                .recordTransfers => try recordTransfers(self),

                .clearBufIR => |bufPassId| try clearBuffer(self, bufPassId, assigner),

                .clearTexIR => |texPassId| try clearTexture(self, texPassId, assigner),
            }
        }

        // Debug Prints
        if (inputData.renderCompilerDebug) {
            std.debug.print("Pass Resource Sys:\n", .{});
            for (0..self.renderNodes.length()) |index| {
                const renderNode = self.renderNodes.get(@intCast(index));
                switch (renderNode) {
                    .passPrint => |*printSpacer| std.debug.print("\nPASS: {s}:\n", .{printSpacer.get()}),
                    .compositePrint => |*printSpacer| std.debug.print("\nCOMPOSITE: {s}:\n", .{printSpacer.get()}),
                    .uiPrint => |*printSpacer| std.debug.print("\nUI: {s}:\n", .{printSpacer.get()}),

                    .clearBuffer => |*clearBuf| std.debug.print("- {}. ClearBuffer: BufId {}\n", .{ index, clearBuf.val() }),
                    .clearTexture => |*clearTex| std.debug.print("- {}. ClearTexture: TexId {}\n", .{ index, clearTex.val() }),

                    // OTHER COMMANDS IN STREAM
                    inline else => |_, tag| std.debug.print("- {}. {s}\n", .{ index, @tagName(tag) }),
                }
            }
            std.debug.print("\n", .{});
        }
    }

    fn updateResourceStates(self: *RenderCompilerData, assigner: *const RenderAssignerData) !void {
        for (0..assigner.requests.length()) |i| {
            const request = assigner.requests.get(@intCast(i));
            // std.debug.print("{}\n", .{request});
            switch (request) {
                .createBuf => |bufId| self.bufStates.upsert(bufId, .{}),
                .createTex => |texId| self.texStates.upsert(texId, .{}),
                .destroyBuf => |bufId| self.bufStates.remove(bufId),
                .destroyTex => |texId| self.texStates.remove(texId),
                .updateBuf => |bufId| try bufBarrier(self, bufId, .Transfer, .TransferWrite),
                .updateTex => |texId| try texBarrier(self, texId, .Transfer, .TransferWrite, .TransferDst, false),
            }
        }
    }

    fn present(self: *RenderCompilerData) !void {
        const timerId = try startTimer(self, "Presentation", .Other);

        for (0..self.swapchainStates.getLength()) |i| {
            const windowId = self.swapchainStates.getKeyByIndex(@intCast(i));
            try self.renderedSwapchains.append(windowId);
            _ = try swapchainBarrier(self, windowId, .BotOfPipe, .None, .PresentSrc);
        }
        try endTimer(self, timerId);
    }

    fn fillCompositePassHardwareIdCmds(self: *RenderCompilerData, assigner: *const RenderAssignerData, _: *const RenderRegistryData, compositeIR: *const CompositeNode) !void {
        const hardwareTexId = assigner.texAssigns.getByKey(compositeIR.srcTexPassId);

        const composite = CompositeFill{
            .name = compositeIR.name,
            .pass = compositeIR.passId,
            .windowId = compositeIR.windowId,
            .srcTexId = hardwareTexId,
            .viewWidth = compositeIR.viewWidth,
            .viewHeight = compositeIR.viewHeight,
            .viewOffsetX = compositeIR.viewOffsetX,
            .viewOffsetY = compositeIR.viewOffsetY,
            .opacity = compositeIR.opacity,
            .stretch = compositeIR.stretch,
        };

        try compositePrint(self, composite.name.get());
        const timerId = try startTimer(self, composite.name.get(), .Composite);

        // Barriers
        const swapchainFirstUse = try swapchainBarrier(self, composite.windowId, .ColorAtt, .ColorAttReadWrite, .Attachment);
        try setColorAttSwapchain(self, composite.windowId, swapchainFirstUse);
        try setOutputExtentSwapchain(self, composite.windowId);
        try texBarrier(self, composite.srcTexId, .Fragment, .SampledRead, .General, false);

        // Shaders
        try setShader(self, sc.compositeFrag.id);
        try setShader(self, sc.compositeVert.id);
        try bindShaders(self);

        const x: f32 = @floatFromInt(composite.viewOffsetX);
        const y: f32 = @floatFromInt(composite.viewOffsetY);
        const viewWidth: f32 = @floatFromInt(composite.viewWidth);
        const viewHeight: f32 = @floatFromInt(composite.viewHeight);
        try setScissor(self, x, y, viewWidth, viewHeight);
        try setViewport(self, x, y, viewWidth, viewHeight);

        // Push Constants

        // const texPassId = try registry.getTexturePassId(drawTex);
        // const texHardwareId = assigner.texAssigns.getByKey(drawTex.texId);
        const stretch: u32 = if (composite.stretch) 1 else 0;
        try setPushDataTexDesc(self, 0 * @sizeOf(u32), composite.srcTexId, .Sampled);
        try setPushData(self, @sizeOf(u32), 1 * @sizeOf(u32), std.mem.asBytes(&rc.SAMPLER_LINEAR_CLAMP_INDEX));
        try setPushData(self, @sizeOf(u32), 2 * @sizeOf(u32), std.mem.asBytes(&stretch));
        try setPushData(self, @sizeOf(u32), 3 * @sizeOf(u32), std.mem.asBytes(&composite.opacity));
        try setPushData(self, @sizeOf(u32), 4 * @sizeOf(u32), std.mem.asBytes(&composite.viewWidth));
        try setPushData(self, @sizeOf(u32), 5 * @sizeOf(u32), std.mem.asBytes(&composite.viewHeight));

        try bindPushData(self);

        // Render State
        try setRenderStateUnion(self, .{ .colorBlend = .True });
        try setRenderStateUnion(self, .{
            .colorBlendEquation = .{
                .srcColor = .SrcAlpha,
                .dstColor = .OneMinusSrcAlpha,
                .colorOperation = .Add,
                .srcAlpha = .One,
                .dstAlpha = .OneMinusSrcAlpha,
                .alphaOperation = .Add,
            },
        });
        try setRenderStateUnion(self, .{ .depthTest = .False });
        try setRenderStateUnion(self, .{ .depthWrite = .False });
        try setRenderStateUnion(self, .{ .cullMode = .None });

        try bindRenderState(self);

        // Rendering
        try beginRendering(self);
        try bindVertexInput(self);
        try bindIndexInput(self); // is this needed?
        try drawVertex(self, .{ .vertexCount = 3, .instanceCount = 1, .firstVertex = 0, .firstInstance = 0 });
        try endRendering(self);

        try resetState(self);

        try endTimer(self, timerId);
    }

    fn fillUiPassHardwareIdCmds(self: *RenderCompilerData, assigner: *const RenderAssignerData, registry: *const RenderRegistryData, uiData: *const UiData, windowData: *const WindowData) !void {
        for (uiData.uiNodes.constSlice()) |uiNode| {
            if (windowData.windows.isKeyUsed(uiNode.windowId.val()) == false) return error.UiRenderCompileCantFindWindowId;

            const imguiVBPassId = try registry.getBufferPassId(uiNode.imguiVB.get());
            const imguiIBPassId = try registry.getBufferPassId(uiNode.imguiIB.get());

            const imguiVB = assigner.bufAssigns.getByKey(imguiVBPassId);
            const imguiIB = assigner.bufAssigns.getByKey(imguiIBPassId);

            try uiPrint(self, uiNode.name.get());

            const timerId = try startTimer(self, uiNode.name.get(), .Ui);

            const uiDrawList = uiData.uiDraws.constSlice()[uiNode.firstDrawIndex..uiNode.lastDrawIndex];

            // Barriers:
            const firstUse = try swapchainBarrier(self, uiNode.windowId, .ColorAtt, .ColorAttReadWrite, .Attachment);
            try setColorAttSwapchain(self, uiNode.windowId, firstUse);
            try setOutputExtentSwapchain(self, uiNode.windowId);
            try bufBarrier(self, imguiVB, .VertexInput, .VertexAttributeRead);
            try bufBarrier(self, imguiIB, .VertexInput, .IndexRead);

            for (uiDrawList) |uiDraw| {
                const texPassId = try registry.getTexturePassId(uiDraw.drawTex.get());
                const drawTex = assigner.texAssigns.getByKey(texPassId);
                try texBarrier(self, drawTex, .Fragment, .SampledRead, .General, false);
            }

            // Shaders
            try setShader(self, sc.imguiVert.id);
            try setShader(self, sc.imguiFrag.id);
            try bindShaders(self);

            // Render State
            try setRenderStateUnion(self, .{ .cullMode = .None });
            try setRenderStateUnion(self, .{ .depthTest = .False });
            try setRenderStateUnion(self, .{ .depthWrite = .False });
            try setRenderStateUnion(self, .{ .colorBlend = .True });
            try setRenderStateUnion(self, .{
                .colorBlendEquation = .{
                    .srcColor = .SrcAlpha,
                    .dstColor = .OneMinusSrcAlpha,
                    .colorOperation = .Add,
                    .srcAlpha = .One,
                    .dstAlpha = .OneMinusSrcAlpha,
                    .alphaOperation = .Add,
                },
            });
            try bindRenderState(self);

            // Rendering
            try beginRendering(self);

            try setViewportFromOutput(self);

            try setVertexBuf(self, .{ .bufId = imguiVB, .binding = 0, .stride = 20, .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX });

            try setVertexAttrib(self, .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 0 });
            try setVertexAttrib(self, .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 8 });
            try setVertexAttrib(self, .{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = 16 });
            try bindVertexInput(self);

            try setIndexBuf(self, .{ .bufId = imguiIB, .indexType = vk.VK_INDEX_TYPE_UINT16 });
            try bindIndexInput(self);

            const window = windowData.windows.getConstPtrByKey(uiNode.windowId.val());

            const scaleX = 2.0 / uiNode.displaySize[0];
            const scaleY = 2.0 / uiNode.displaySize[1];
            const translateX = -1.0 - uiNode.displayPos[0] * scaleX;
            const translateY = -1.0 - uiNode.displayPos[1] * scaleY;
            const windowWidth = @as(f32, @floatFromInt(window.extent.width)); // Was Swapchain before
            const windowHeight = @as(f32, @floatFromInt(window.extent.height)); // Was Swapchain before

            for (uiDrawList) |uiDraw| {
                const x0 = @max(0.0, @min(uiDraw.clipRect[0] - uiNode.displayPos[0], windowWidth));
                const y0 = @max(0.0, @min(uiDraw.clipRect[1] - uiNode.displayPos[1], windowHeight));
                const x1 = @max(x0, @min(uiDraw.clipRect[2] - uiNode.displayPos[0], windowWidth));
                const y1 = @max(y0, @min(uiDraw.clipRect[3] - uiNode.displayPos[1], windowHeight));
                if (x1 - x0 <= 0 or y1 - y0 <= 0) continue;

                try setScissor(self, x0, y0, x1 - x0, y1 - y0);

                try setPushData(self, @sizeOf(u32), 0 * @sizeOf(u32), std.mem.asBytes(&scaleX));
                try setPushData(self, @sizeOf(u32), 1 * @sizeOf(u32), std.mem.asBytes(&scaleY));
                try setPushData(self, @sizeOf(u32), 2 * @sizeOf(u32), std.mem.asBytes(&translateX));
                try setPushData(self, @sizeOf(u32), 3 * @sizeOf(u32), std.mem.asBytes(&translateY));

                const texPassId = try registry.getTexturePassId(uiDraw.drawTex.get());
                const drawTex = assigner.texAssigns.getByKey(texPassId);
                try setPushDataTexDesc(self, (4 * @sizeOf(u32)), drawTex, .Sampled);

                try bindPushData(self);
                try drawVertexIndexed(self, .{ .indexCount = uiDraw.elemCount, .instanceCount = 1, .firstIndex = uiDraw.idxOffset, .vertexOffset = uiDraw.vtxOffset, .firstInstance = 0 });
            }

            try endRendering(self);
            try resetState(self);

            try endTimer(self, timerId);
        }
    }

    fn fillPassHardwareIdCmds(
        self: *RenderCompilerData,
        assigner: *const RenderAssignerData,
        registry: *const RenderRegistryData,
        passId: PassId,
        runTime: f32,
        deltaTime: f32,
    ) !void {
        const passName = try registry.getPassName(passId);
        const pass = try registry.getPass(passName);
        const mainOutputTexId = pass.outputTex;
        const mainOutputTexHardwareId = if (mainOutputTexId) |outputId| assigner.texAssigns.getByKey(outputId) else null;

        const timerId = try startTimer(self, passName, .Pass);

        try startStats(self, passName);

        try setOutputExtent(self, mainOutputTexHardwareId);

        var pushOffset: u32 = 0;

        try setPushData(self, 1 * @sizeOf(u32), pushOffset, std.mem.asBytes(&runTime));
        pushOffset += @sizeOf(f32);

        try setPushData(self, 1 * @sizeOf(u32), pushOffset, std.mem.asBytes(&deltaTime));
        pushOffset += @sizeOf(f32);

        try setPushDataOutputExtent(self, pushOffset);
        pushOffset += @sizeOf(f32) + @sizeOf(f32);

        for (pass.passProperties.constSlice()) |attribute| {
            switch (attribute) {
                .shaderInf => |shaderInf| {
                    try setShader(self, shaderInf.id);
                },
                .bufSlot => |bufSlot| {
                    const bufHardwareId = assigner.bufAssigns.getByKey(bufSlot.bufLink.in);
                    try bufBarrier(self, bufHardwareId, bufSlot.stage, bufSlot.access);

                    if (bufSlot.shaderSlot) |slot| try setPushDataBufDesc(self, pushOffset + (slot * @sizeOf(u32)), bufHardwareId);
                },
                .texSlot => |texSlot| {
                    const texHardwareId = assigner.texAssigns.getByKey(texSlot.texLink.in);
                    try texBarrier(self, texHardwareId, texSlot.stage, texSlot.access, texSlot.layout, false);

                    if (texSlot.shaderSlot) |slot| try setPushDataTexDesc(self, pushOffset + (slot * @sizeOf(u32)), texHardwareId, texSlot.descUse);
                },

                .colorAtt => |attSlot| {
                    const texPassId = attSlot.texLink.in;
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);

                    if (attSlot.clear) |clear| {
                        // Manually Set Clear
                        switch (clear) {
                            .color => |color| {
                                try texBarrier(self, texHardwareId, attSlot.stage, attSlot.access, attSlot.layout, false);
                                try setColorAtt(self, texHardwareId, color);
                            },
                            .depth => return error.ColorAttNeedsColorClear,
                        }
                    } else {
                        try texBarrier(self, texHardwareId, attSlot.stage, attSlot.access, attSlot.layout, false);
                        try setColorAtt(self, texHardwareId, null);
                    }
                },
                .depthAtt => |depthSlot| {
                    const texPassId = depthSlot.texLink.in;
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);

                    if (depthSlot.clear) |clear| {
                        // Manually Set Clear
                        switch (clear) {
                            .depth => |depth| {
                                try texBarrier(self, texHardwareId, depthSlot.stage, depthSlot.access, depthSlot.layout, false);
                                try setDepthAtt(self, texHardwareId, depth);
                            },
                            .color => return error.DepthAttNeedsDepthClear,
                        }
                    } else {
                        try texBarrier(self, texHardwareId, depthSlot.stage, depthSlot.access, depthSlot.layout, false);
                        try setDepthAtt(self, texHardwareId, null);
                    }
                },
                .stencilAtt => |stencilSlot| {
                    const texPassId = stencilSlot.texLink.in;
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);

                    if (stencilSlot.clear) |clear| {
                        // Manually Set Clear
                        switch (clear) {
                            .depth => |depth| {
                                try texBarrier(self, texHardwareId, stencilSlot.stage, stencilSlot.access, stencilSlot.layout, false);
                                try setStencilAtt(self, texHardwareId, depth);
                            },
                            .color => return error.StencilAttNeedsDepthClear,
                        }
                    } else {
                        try texBarrier(self, texHardwareId, stencilSlot.stage, stencilSlot.access, stencilSlot.layout, false);
                        try setStencilAtt(self, texHardwareId, null);
                    }
                },

                .vertexBuffer => |vertBufSlot| {
                    const bufHardwareId = assigner.bufAssigns.getByKey(vertBufSlot.bufPassId);
                    try bufBarrier(self, bufHardwareId, .VertexInput, .VertexAttributeRead);
                    try setVertexBuf(self, .{ .bufId = bufHardwareId, .binding = vertBufSlot.binding, .stride = vertBufSlot.stride, .inputRate = vertBufSlot.inputRate });
                },
                .indexBuffer => |indexBufSlot| {
                    const bufHardwareId = assigner.bufAssigns.getByKey(indexBufSlot.bufPassId);
                    try bufBarrier(self, bufHardwareId, .VertexInput, .IndexRead);
                    try setIndexBuf(self, .{ .bufId = bufHardwareId, .indexType = indexBufSlot.indexType });
                },
                .vertexAttribute => |vertAttrib| {
                    try setVertexAttrib(self, vertAttrib);
                },
                .renderState => |stateChange| {
                    try setRenderStateUnion(self, stateChange);
                },
                .bufLink, .texLink, .passLink => {},
            }
        }

        try bindShaders(self);
        try bindPushData(self);

        switch (pass.execution) {
            .compute => |comp| {
                if (comp.outputTexDispatch == true) {
                    if (mainOutputTexHardwareId) |outputTexId| {
                        try dispatchOutputTex(self, comp.groupX, comp.groupY, comp.groupZ, outputTexId);
                    } else return error.outputTexDispatchHasNoMainOutput;
                } else try dispatch(self, comp.groupX, comp.groupY, comp.groupZ);
            },
            .computeIndirect => |compIndirect| {
                const bufHardwareId = assigner.bufAssigns.getByKey(compIndirect.indirectBuf);
                try dispatchIndirect(self, bufHardwareId, compIndirect.indirectBufOffset);
            },
            .vertex => |vertex| {
                try bindRenderState(self);
                try beginRendering(self);
                try setViewportFromOutput(self);
                try setScissorFromOutput(self);
                try bindVertexInput(self);
                try bindIndexInput(self);
                try drawVertex(self, vertex);
                try endRendering(self);
            },
            .vertexIndexed => |vertexIndexed| {
                try bindRenderState(self);
                try beginRendering(self);
                try setViewportFromOutput(self);
                try setScissorFromOutput(self);
                try bindVertexInput(self);
                try bindIndexInput(self);
                try drawVertexIndexed(self, vertexIndexed);
                try endRendering(self);
            },
            .taskOrMesh => |taskOrMesh| {
                try bindRenderState(self);
                try beginRendering(self);
                try setViewportFromOutput(self);
                try setScissorFromOutput(self);
                try drawTaskOrMesh(self, taskOrMesh);
                try endRendering(self);
            },
            .taskOrMeshIndirect => |taskOrMeshIndirect| {
                try bindRenderState(self);
                try beginRendering(self);
                try setViewportFromOutput(self);
                try setScissorFromOutput(self);

                const bufHardwareId = assigner.bufAssigns.getByKey(taskOrMeshIndirect.indirectBufId);
                try drawTaskOrMeshIndirect(self, .{ .indirectBufId = bufHardwareId, .drawCount = 1, .bufOffset = taskOrMeshIndirect.bufOffset, .stride = @sizeOf(vhT.IndirectData) });

                try endRendering(self);
            },
        }

        try resetState(self);

        try endTimer(self, timerId);
        try endStats(self);
    }

    // String Spacers

    fn uiPrint(self: *RenderCompilerData, name: []const u8) !void {
        try self.tempNodes.append(.{ .uiPrint = try .string(name) });
    }

    fn passPrint(self: *RenderCompilerData, name: []const u8) !void {
        try self.tempNodes.append(.{ .passPrint = try .string(name) });
    }

    fn compositePrint(self: *RenderCompilerData, name: []const u8) !void {
        try self.tempNodes.append(.{ .compositePrint = try .string(name) });
    }

    // Graph Commands

    fn clearBuffer(self: *RenderCompilerData, bufPassId: BufPassId, assigner: *const RenderAssignerData) !void {
        const bufId = assigner.bufAssigns.getByKey(bufPassId);
        try bufBarrier(self, bufId, .Clear, .TransferWrite);
        try self.tempNodes.append(.{ .clearBuffer = bufId });
    }

    fn clearTexture(self: *RenderCompilerData, texPassId: TexPassId, assigner: *const RenderAssignerData) !void {
        const texId = assigner.texAssigns.getByKey(texPassId);
        try texBarrier(self, texId, .Clear, .TransferWrite, .TransferDst, true);
        try self.tempNodes.append(.{ .clearTexture = texId });
    }

    // Barrier Commands
    fn recordTransfers(self: *RenderCompilerData) !void {
        try self.renderNodes.append(.recordTransfers);
    }

    fn bufBarrier(self: *RenderCompilerData, bufId: BufId, newStage: vhE.PipeStage, newAccess: vhE.PipeAccess) !void {
        const state = self.bufStates.getPtrByKey(bufId);
        const dstStage: u64 = @intFromEnum(newStage);
        const dstAccess: u64 = @intFromEnum(newAccess);
        const isRead = newAccess.isReadOnly();

        const alreadyLetIn = isRead and state.readStages & dstStage == dstStage and state.readAccess & dstAccess == dstAccess;

        if (alreadyLetIn == false) {
            const joinsReaders = isRead and rc.USE_RESOURCE_BARRIER_READ_TRACK;
            var mask: BarrierMask = .{};

            if (joinsReaders) {
                state.readStages |= dstStage;
                state.readAccess |= dstAccess;
                mask = BarrierMask{ .srcStage = state.writeStage, .srcAccess = state.writeAccess, .dstStage = state.readStages, .dstAccess = state.readAccess };
            } else {
                mask = BarrierMask{ .srcStage = state.writeStage | state.readStages, .srcAccess = state.writeAccess | state.readAccess, .dstStage = dstStage, .dstAccess = dstAccess };
                state.* = BarrierState{ .writeStage = dstStage, .writeAccess = dstAccess, .readStages = if (isRead) dstStage else 0, .readAccess = if (isRead) dstAccess else 0 };
            }

            if (rc.USE_MEM_BARRIERS_ON_BUFFERS) {
                self.mask.merge(mask);
                self.memBarrierUse = true;
            } else {
                try self.renderNodes.append(.{ .bufBarrier = .{ .bufId = bufId, .mask = mask } });
            }
        }
    }

    fn texBarrier(self: *RenderCompilerData, texId: TexId, newStage: vhE.PipeStage, newAccess: vhE.PipeAccess, newLayout: vhE.ImageLayout, ignoreOld: bool) !void {
        const state = self.texStates.getPtrByKey(texId);

        const dstStage: u64 = @intFromEnum(newStage);
        const dstAccess: u64 = @intFromEnum(newAccess);
        const isRead = newAccess.isReadOnly();
        const oldLayout: vhE.ImageLayout = if (ignoreOld) .Undefined else state.layout;

        const alreadyLetIn = isRead and oldLayout == newLayout and state.readStages & dstStage == dstStage and state.readAccess & dstAccess == dstAccess;

        if (alreadyLetIn == false) {
            const joinsReaders = isRead and oldLayout == newLayout and rc.USE_RESOURCE_BARRIER_READ_TRACK;
            var mask: BarrierMask = .{};

            if (joinsReaders) {
                state.readStages |= dstStage;
                state.readAccess |= dstAccess;
                mask = BarrierMask{ .srcStage = state.writeStage, .srcAccess = state.writeAccess, .dstStage = state.readStages, .dstAccess = state.readAccess };
            } else {
                mask = BarrierMask{ .srcStage = state.writeStage | state.readStages, .srcAccess = state.writeAccess | state.readAccess, .dstStage = dstStage, .dstAccess = dstAccess };
                state.* = TextureState{ .writeStage = dstStage, .writeAccess = dstAccess, .readStages = if (isRead) dstStage else 0, .readAccess = if (isRead) dstAccess else 0, .layout = newLayout };
            }

            if (rc.USE_MEM_BARRIER_ON_IMAGES and oldLayout == newLayout) {
                self.mask.merge(mask);
                self.memBarrierUse = true;
            } else {
                try self.renderNodes.append(.{ .texBarrier = .{ .texId = texId, .mask = mask, .oldLayout = oldLayout, .newLayout = newLayout } });
            }
        }
    }

    fn swapchainBarrier(self: *RenderCompilerData, windowId: WindowId, newStage: vhE.PipeStage, newAccess: vhE.PipeAccess, newLayout: vhE.ImageLayout) !bool {
        const dstStage: u64 = @intFromEnum(newStage);
        const dstAccess: u64 = @intFromEnum(newAccess);

        const firstUse = self.swapchainStates.isKeyUsed(windowId) == false;
        if (firstUse) self.swapchainStates.insert(windowId, TextureState{ .writeStage = @intFromEnum(vhE.PipeStage.ColorAtt) });

        const state = self.swapchainStates.getPtrByKey(windowId);
        const mask = BarrierMask{ .srcStage = state.writeStage, .srcAccess = state.writeAccess, .dstStage = dstStage, .dstAccess = dstAccess };

        if (rc.USE_MEM_BARRIER_ON_IMAGES and state.layout == newLayout) {
            self.mask.merge(mask);
            self.memBarrierUse = true;
        } else {
            try self.renderNodes.append(.{ .swapchainBarrier = .{ .windowId = windowId, .mask = mask, .oldLayout = state.layout, .newLayout = newLayout } });
        }

        state.writeStage = dstStage;
        state.writeAccess = dstAccess;
        state.layout = newLayout;

        return firstUse;
    }

    fn bakeBarriers(self: *RenderCompilerData) !void {
        if (self.memBarrierUse) try self.renderNodes.append(.{ .memBarrier = .{ .mask = self.mask } });

        try self.renderNodes.append(.bakeBarriers);

        for (0..self.tempNodes.length()) |i| {
            const renderNode = self.tempNodes.get(@intCast(i));
            try self.renderNodes.append(renderNode);
        }

        self.memBarrierUse = false;
        self.tempNodes.clear();
        self.mask = .{};
    }

    // Profiling Commands

    fn startTimer(self: *RenderCompilerData, name: []const u8, typ: QueryTyp) !u8 {
        const timerId = self.usedQueries;
        try self.tempNodes.append(.{ .startTimer = .{ .name = try .string(name), .typ = typ, .pipeStage = .AllCmds, .queryId = timerId } });
        self.usedQueries += 1;
        return timerId;
    }

    fn endTimer(self: *RenderCompilerData, timerId: u8) !void {
        try self.tempNodes.append(.{ .endTimer = .{ .pipeStage = .BotOfPipe, .queryId = timerId } });
    }

    fn startStats(self: *RenderCompilerData, name: []const u8) !void {
        try self.tempNodes.append(.{ .startStats = try .string(name) });
    }

    fn endStats(self: *RenderCompilerData) !void {
        try self.tempNodes.append(.endStats);
    }

    // Pass Commands

    fn setShader(self: *RenderCompilerData, shaderId: ShaderId) !void {
        try self.tempNodes.append(.{ .setShader = shaderId });
    }

    fn bindShaders(self: *RenderCompilerData) !void {
        try self.tempNodes.append(.bindShaders);
    }

    fn setPushData(self: *RenderCompilerData, len: u8, offset: u32, dataBytes: []const u8) !void {
        try self.tempNodes.append(.{ .setPushData = .{ .startIndex = self.pushData.len, .len = len, .offset = offset } });
        self.pushData.appendSliceAssumeCapacity(dataBytes);
    }

    fn setPushDataOutputExtent(self: *RenderCompilerData, offset: u32) !void {
        try self.tempNodes.append(.{ .setPushDataOutputExtent = .{ .offset = offset } });
    }

    fn setPushDataBufDesc(self: *RenderCompilerData, offset: u32, bufId: BufId) !void {
        try self.tempNodes.append(.{ .setPushDataBufDesc = .{ .bufId = bufId, .size = @sizeOf(u32), .offset = offset } });
    }

    fn setPushDataTexDesc(self: *RenderCompilerData, offset: u32, texId: TexId, descTyp: vhE.TexDescriptor) !void {
        try self.tempNodes.append(.{ .setPushDataTexDesc = .{ .texId = texId, .size = @sizeOf(u32), .offset = offset, .descTyp = descTyp } });
    }

    fn bindPushData(self: *RenderCompilerData) !void {
        try self.tempNodes.append(.bindPushData);
    }

    fn dispatch(self: *RenderCompilerData, groupX: u32, groupY: u32, groupZ: u32) !void {
        try self.tempNodes.append(.{ .dispatch = .{ .groupX = groupX, .groupY = groupY, .groupZ = groupZ } });
    }

    fn dispatchOutputTex(self: *RenderCompilerData, groupX: u32, groupY: u32, groupZ: u32, texId: TexId) !void {
        try self.tempNodes.append(.{ .dispatchOutputTex = .{ .groupX = groupX, .groupY = groupY, .groupZ = groupZ, .texId = texId } });
    }

    fn dispatchIndirect(self: *RenderCompilerData, indirectBufId: BufId, indirectBufOffset: u64) !void {
        try self.tempNodes.append(.{ .dispatchIndirect = .{ .indirectBufId = indirectBufId, .indirectBufOffset = indirectBufOffset } });
    }

    fn setOutputExtentSwapchain(self: *RenderCompilerData, windowId: WindowId) !void {
        try self.tempNodes.append(.{ .setOutputExtentSwapchain = windowId });
    }

    fn setOutputExtent(self: *RenderCompilerData, texId: ?TexId) !void {
        try self.tempNodes.append(.{ .setOutputExtent = texId });
    }

    // Draw Commands

    fn beginRendering(self: *RenderCompilerData) !void {
        try self.tempNodes.append(.beginRendering);
    }

    fn setViewport(self: *RenderCompilerData, x: f32, y: f32, width: f32, height: f32) !void {
        try self.tempNodes.append(.{ .setViewport = .{ .x = x, .y = y, .width = width, .height = height } });
    }

    fn setViewportFromTex(self: *RenderCompilerData, texId: TexId) !void {
        try self.tempNodes.append(.{ .setViewportFromTex = texId });
    }

    fn setViewportFromOutput(self: *RenderCompilerData) !void {
        try self.tempNodes.append(.setViewportFromOutput);
    }

    fn setScissor(self: *RenderCompilerData, x: f32, y: f32, width: f32, height: f32) !void {
        try self.tempNodes.append(.{ .setScissor = .{ .x = x, .y = y, .width = width, .height = height } });
    }

    fn setScissorFromTex(self: *RenderCompilerData, texId: TexId) !void {
        try self.tempNodes.append(.{ .setScissorFromTex = texId });
    }

    fn setScissorFromOutput(self: *RenderCompilerData) !void {
        try self.tempNodes.append(.setScissorFromOutput);
    }

    fn setRenderStateUnion(self: *RenderCompilerData, renderStateUnion: RenderStateUnion) !void {
        try self.tempNodes.append(.{ .setRenderStateUnion = renderStateUnion });
    }

    fn bindRenderState(self: *RenderCompilerData) !void {
        try self.tempNodes.append(.bindRenderState);
    }

    fn setColorAttSwapchain(self: *RenderCompilerData, windowId: WindowId, firstUse: bool) !void {
        try self.tempNodes.append(.{ .setColorAttSwapchain = .{ .windowId = windowId, .firstUse = firstUse } });
    }

    fn setColorAtt(self: *RenderCompilerData, texId: TexId, clear: ?ClearColor) !void {
        try self.tempNodes.append(.{ .setColorAtt = .{ .texId = texId, .clear = clear } });
    }

    fn setDepthAtt(self: *RenderCompilerData, texId: TexId, clear: ?ClearDepth) !void {
        try self.tempNodes.append(.{ .setDepthAtt = .{ .texId = texId, .clear = clear } });
    }

    fn setStencilAtt(self: *RenderCompilerData, texId: TexId, clear: ?ClearDepth) !void {
        try self.tempNodes.append(.{ .setStencilAtt = .{ .texId = texId, .clear = clear } });
    }

    fn setIndexBuf(self: *RenderCompilerData, indexBufferUse: IndexBufferUse) !void {
        try self.tempNodes.append(.{ .setIndexBuf = indexBufferUse });
    }

    fn bindIndexInput(self: *RenderCompilerData) !void {
        try self.tempNodes.append(.bindIndexInput);
    }

    fn setVertexBuf(self: *RenderCompilerData, vertexBufferUse: VertexBufferUse) !void {
        try self.tempNodes.append(.{ .setVertexBuf = vertexBufferUse });
    }

    fn setVertexAttrib(self: *RenderCompilerData, vertexAttribute: VertexAttribute) !void {
        try self.tempNodes.append(.{ .setVertexAttrib = vertexAttribute });
    }

    fn bindVertexInput(self: *RenderCompilerData) !void {
        try self.tempNodes.append(.bindVertexInput);
    }

    fn drawVertex(self: *RenderCompilerData, vertexExec: VertexExec) !void {
        try self.tempNodes.append(.{ .drawVertex = vertexExec });
    }

    fn drawVertexIndexed(self: *RenderCompilerData, vertexIndexedExec: VertexIndexedExec) !void {
        try self.tempNodes.append(.{ .drawVertexIndexed = vertexIndexedExec });
    }

    fn drawTaskOrMesh(self: *RenderCompilerData, taskOrMeshExec: TaskOrMeshExec) !void {
        try self.tempNodes.append(.{ .drawTaskOrMesh = taskOrMeshExec });
    }

    fn drawTaskOrMeshIndirect(self: *RenderCompilerData, taskOrMeshIndirectExec: TaskOrMeshIndirectExec) !void {
        try self.tempNodes.append(.{ .drawTaskOrMeshIndirect = taskOrMeshIndirectExec });
    }

    fn endRendering(self: *RenderCompilerData) !void {
        try self.tempNodes.append(.endRendering);
    }

    fn resetState(self: *RenderCompilerData) !void {
        try self.tempNodes.append(.resetState);
    }
};
