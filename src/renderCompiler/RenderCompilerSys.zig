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
const TextureState = @import("../render/types/res/Texture.zig").Texture.TextureState;
const CompositeFill = @import("../render/types/pass/RenderNode.zig").CompositeFill;
const CompositeNode = @import("../render/types/pass/RenderNode.zig").CompositeNode;
const BufferState = @import("../render/types/res/Buffer.zig").Buffer.BufferState;
const VertexExec = @import("../render/types/pass/PassDefinition.zig").VertexExec;
const RenderCompilerData = @import("RenderCompilerData.zig").RenderCompilerData;
const ClearColor = @import("../render/types/pass/AttachmentUse.zig").ClearColor;
const ClearDepth = @import("../render/types/pass/AttachmentUse.zig").ClearDepth;
const RenderState = @import("../render/types/pass/RenderState.zig").RenderState;
const TextureFill = @import("../render/types/pass/TextureUse.zig").TextureFill;
const RenderNode = @import("../render/types/pass/RenderNode.zig").RenderNode;
const BufferFill = @import("../render/types/pass/BufferUse.zig").BufferFill;
const QueryTyp = @import("../render/types/base/Cmd.zig").QueryPair.QueryTyp;
const WindowData = @import("../window/WindowData.zig").WindowData;
const WindowId = @import("../.configs/idConfig.zig").WindowId;
const ShaderId = @import("../.configs/idConfig.zig").ShaderId;
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
        runTime: f32,
        deltaTime: f32,
    ) !void {
        self.swapchainStates.clear();
        self.renderedSwapchains.clear();
        self.sortedNodes.clear();
        self.pushData.clear();
        self.usedQueries = 0;

        updateResourceStates(self, assigner);

        recordTransfers(self);

        for (renderGraph.sorter.sortedRenderIR.constSlice()) |IR| {
            switch (IR) {
                // .uiIR => |uiIR| {},
                .compositeIR => |*compositeIR| try fillCompositePassHardwareIdCmds(self, assigner, registry, compositeIR),
                .passIR => |passIR| try fillPassHardwareIdCmds(self, assigner, registry, renderGraph, passIR, runTime, deltaTime),
            }
        }

        // Build UI Passes
        try fillUiPassHardwareIdCmds(self, assigner, registry, uiData, windowData);

        try present(self);

        // Debug Prints
        if (rc.RENDER_COMPILER_DEBUG) {
            std.debug.print("Pass Resource Sys:\n", .{});
            for (self.sortedNodes.constSlice(), 0..) |*renderNode, index| {
                switch (renderNode.*) {
                    .passPrint => |*printSpacer| std.debug.print("\nPASS: {s}:\n", .{printSpacer.get()}),
                    .compositePrint => |*printSpacer| std.debug.print("\nCOMPOSITE: {s}:\n", .{printSpacer.get()}),
                    .uiPrint => |*printSpacer| std.debug.print("\nUI: {s}:\n", .{printSpacer.get()}),

                    .clearBuffer => |*clearBuf| std.debug.print("- {}. ClearBuffer: BufId {}\n", .{ index, clearBuf.val() }),
                    .clearTexture => |*clearTex| std.debug.print("- {}. ClearTexture: TexId {}\n", .{ index, clearTex.val() }),

                    // OTHER COMMAND IN STREAM
                    inline else => |_, tag| std.debug.print("- {}. {s}\n", .{ index, @tagName(tag) }),
                }
            }
            std.debug.print("\n", .{});
        }
    }

    fn updateResourceStates(self: *RenderCompilerData, assigner: *const RenderAssignerData) void {
        for (assigner.requests.constSlice()) |request| {
            // std.debug.print("{}\n", .{request});
            switch (request) {
                .createBuf => |bufId| self.bufStates.upsert(bufId, .{}),
                .createTex => |texId| self.texStates.upsert(texId, .{}),
                .destroyBuf => |bufId| self.bufStates.remove(bufId),
                .destroyTex => |texId| self.texStates.remove(texId),
                .updateBuf => |bufId| bufBarrier(self, bufId, .Transfer, .TransferWrite),
                .updateTex => |texId| texBarrier(self, texId, .Transfer, .TransferWrite, .TransferDst, false),
            }
        }
        bakeBarriers(self);
    }

    fn present(self: *RenderCompilerData) !void {
        const timerId = try startTimer(self, "Presentation", .Other);

        for (0..self.swapchainStates.getLength()) |i| {
            const windowId = self.swapchainStates.getKeyByIndex(@intCast(i));
            try self.renderedSwapchains.append(windowId);
            _ = swapchainTargetBarrier(self, windowId, .BotOfPipe, .None, .PresentSrc);
        }
        bakeBarriers(self);
        endTimer(self, timerId);
    }

    fn fillCompositePassHardwareIdCmds(self: *RenderCompilerData, assigner: *const RenderAssignerData, _: *const RenderRegistryData, compositeIR: *const CompositeNode) !void {
        const hardwareTexId = assigner.texAssigns.getByKey(compositeIR.srcTexPassId);

        const composite = CompositeFill{
            .name = compositeIR.name,
            .pass = compositeIR.pass,
            .windowId = compositeIR.windowId,
            .srcTexId = hardwareTexId,
            .viewWidth = compositeIR.viewWidth,
            .viewHeight = compositeIR.viewHeight,
            .viewOffsetX = compositeIR.viewOffsetX,
            .viewOffsetY = compositeIR.viewOffsetY,
            .opacity = compositeIR.opacity,
            .stretch = compositeIR.stretch,
        };

        try compositePrint(self, composite.name);
        const timerId = try startTimer(self, composite.name, .Composite);

        // Barriers
        const swapchainFirstUse = swapchainTargetBarrier(self, composite.windowId, .ColorAtt, .ColorAttReadWrite, .Attachment);
        setColorAttSwapchain(self, composite.windowId, swapchainFirstUse);
        setOutputExtentSwapchain(self, composite.windowId);
        texBarrier(self, composite.srcTexId, .Fragment, .SampledRead, .General, false);
        bakeBarriers(self);

        // Shaders
        setShader(self, sc.compositeFrag.id);
        setShader(self, sc.compositeVert.id);
        bindShaders(self);

        const x: f32 = @floatFromInt(composite.viewOffsetX);
        const y: f32 = @floatFromInt(composite.viewOffsetY);
        const viewWidth: f32 = @floatFromInt(composite.viewWidth);
        const viewHeight: f32 = @floatFromInt(composite.viewHeight);
        setScissor(self, x, y, viewWidth, viewHeight);
        setViewport(self, x, y, viewWidth, viewHeight);

        // Push Constants

        // const texPassId = try registry.getTexturePassId(drawTex);
        // const texHardwareId = assigner.texAssigns.getByKey(drawTex.texId);
        const stretch: u32 = if (composite.stretch) 1 else 0;
        setPushDataTexDesc(self, 0 * @sizeOf(u32), composite.srcTexId, .Sampled);
        setPushData(self, @sizeOf(u32), 1 * @sizeOf(u32), std.mem.asBytes(&rc.SAMPLER_LINEAR_CLAMP_INDEX));
        setPushData(self, @sizeOf(u32), 2 * @sizeOf(u32), std.mem.asBytes(&stretch));
        setPushData(self, @sizeOf(u32), 3 * @sizeOf(u32), std.mem.asBytes(&composite.opacity));
        setPushData(self, @sizeOf(u32), 4 * @sizeOf(u32), std.mem.asBytes(&composite.viewWidth));
        setPushData(self, @sizeOf(u32), 5 * @sizeOf(u32), std.mem.asBytes(&composite.viewHeight));

        bindPushData(self);

        // Render State
        setRenderStateUnion(self, .{ .colorBlend = .True });
        setRenderStateUnion(self, .{
            .colorBlendEquation = .{
                .srcColor = .SrcAlpha,
                .dstColor = .OneMinusSrcAlpha,
                .colorOperation = .Add,
                .srcAlpha = .One,
                .dstAlpha = .OneMinusSrcAlpha,
                .alphaOperation = .Add,
            },
        });
        setRenderStateUnion(self, .{ .depthTest = .False });
        setRenderStateUnion(self, .{ .depthWrite = .False });
        setRenderStateUnion(self, .{ .cullMode = .None });

        bindRenderState(self);

        // Rendering
        beginRendering(self);
        bindVertexInput(self);
        bindIndexInput(self); // is this needed?
        drawVertex(self, .{ .vertexCount = 3, .instanceCount = 1, .firstVertex = 0, .firstInstance = 0 });
        endRendering(self);

        resetState(self);

        endTimer(self, timerId);
    }

    fn fillUiPassHardwareIdCmds(self: *RenderCompilerData, assigner: *const RenderAssignerData, registry: *const RenderRegistryData, uiData: *const UiData, windowData: *const WindowData) !void {
        for (uiData.uiNodes.constSlice()) |uiNode| {
            if (windowData.windows.isKeyUsed(uiNode.windowId.val()) == false) return error.UiRenderCompileCantFindWindowId;

            const imguiVBPassId = try registry.getBufferPassId(uiNode.imguiVB);
            const imguiIBPassId = try registry.getBufferPassId(uiNode.imguiIB);

            const imguiVB = assigner.bufAssigns.getByKey(imguiVBPassId);
            const imguiIB = assigner.bufAssigns.getByKey(imguiIBPassId);

            try uiPrint(self, uiNode.name);

            const timerId = try startTimer(self, uiNode.name, .Ui);

            const uiDrawList = uiData.uiDraws.constSlice()[uiNode.firstDrawIndex..uiNode.lastDrawIndex];

            // Barriers:
            const firstUse = swapchainTargetBarrier(self, uiNode.windowId, .ColorAtt, .ColorAttReadWrite, .Attachment);
            setColorAttSwapchain(self, uiNode.windowId, firstUse);
            setOutputExtentSwapchain(self, uiNode.windowId);
            bufBarrier(self, imguiVB, .VertexInput, .VertexAttributeRead);
            bufBarrier(self, imguiIB, .VertexInput, .IndexRead);

            for (uiDrawList) |uiDraw| {
                const texPassId = try registry.getTexturePassId(uiDraw.drawTex);
                const drawTex = assigner.texAssigns.getByKey(texPassId);
                texBarrier(self, drawTex, .Fragment, .SampledRead, .General, false);
            }
            bakeBarriers(self);

            // Shaders
            setShader(self, sc.imguiVert.id);
            setShader(self, sc.imguiFrag.id);
            bindShaders(self);

            // Render State
            setRenderStateUnion(self, .{ .cullMode = .None });
            setRenderStateUnion(self, .{ .depthTest = .False });
            setRenderStateUnion(self, .{ .depthWrite = .False });
            setRenderStateUnion(self, .{ .colorBlend = .True });
            setRenderStateUnion(self, .{
                .colorBlendEquation = .{
                    .srcColor = .SrcAlpha,
                    .dstColor = .OneMinusSrcAlpha,
                    .colorOperation = .Add,
                    .srcAlpha = .One,
                    .dstAlpha = .OneMinusSrcAlpha,
                    .alphaOperation = .Add,
                },
            });
            bindRenderState(self);

            // Rendering
            beginRendering(self);

            setViewportFromOutput(self);

            setVertexBuf(self, .{ .bufId = imguiVB, .binding = 0, .stride = 20, .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX });

            setVertexAttrib(self, .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 0 });
            setVertexAttrib(self, .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 8 });
            setVertexAttrib(self, .{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = 16 });
            bindVertexInput(self);

            setIndexBuf(self, .{ .bufId = imguiIB, .indexType = vk.VK_INDEX_TYPE_UINT16 });
            bindIndexInput(self);

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

                setScissor(self, x0, y0, x1 - x0, y1 - y0);

                setPushData(self, @sizeOf(u32), 0 * @sizeOf(u32), std.mem.asBytes(&scaleX));
                setPushData(self, @sizeOf(u32), 1 * @sizeOf(u32), std.mem.asBytes(&scaleY));
                setPushData(self, @sizeOf(u32), 2 * @sizeOf(u32), std.mem.asBytes(&translateX));
                setPushData(self, @sizeOf(u32), 3 * @sizeOf(u32), std.mem.asBytes(&translateY));

                const texPassId = try registry.getTexturePassId(uiDraw.drawTex);
                const drawTex = assigner.texAssigns.getByKey(texPassId);
                setPushDataTexDesc(self, (4 * @sizeOf(u32)), drawTex, .Sampled);

                bindPushData(self);
                drawVertexIndexed(self, .{ .indexCount = uiDraw.elemCount, .instanceCount = 1, .firstIndex = uiDraw.idxOffset, .vertexOffset = uiDraw.vtxOffset, .firstInstance = 0 });
            }

            endRendering(self);
            resetState(self);

            endTimer(self, timerId);
        }
    }

    fn fillPassHardwareIdCmds(
        self: *RenderCompilerData,
        assigner: *const RenderAssignerData,
        registry: *const RenderRegistryData,
        renderGraph: *const RenderGraphData,
        passId: PassId,
        runTime: f32,
        deltaTime: f32,
    ) !void {
        const passName = try registry.getPassName(passId);
        const pass = try registry.getPass(passName);
        const mainOutputTexId = pass.outputTex;
        const mainOutputTexHardwareId = if (mainOutputTexId) |outputId| assigner.texAssigns.getByKey(outputId) else null;

        try passPrint(self, passName);
        const timerId = try startTimer(self, passName, .Pass);
        try startStats(self, passName);

        setOutputExtent(self, mainOutputTexHardwareId);

        var pushOffset: u32 = 0;

        setPushData(self, 1 * @sizeOf(u32), pushOffset, std.mem.asBytes(&runTime));
        pushOffset += @sizeOf(f32);

        setPushData(self, 1 * @sizeOf(u32), pushOffset, std.mem.asBytes(&deltaTime));
        pushOffset += @sizeOf(f32);

        setPushDataOutputExtent(self, pushOffset);
        pushOffset += @sizeOf(f32) + @sizeOf(f32);

        var needsClearBarrier: bool = false;

        for (pass.passProperties.constSlice()) |attribute| {
            switch (attribute) {
                .shaderInf, .colorAtt, .depthAtt, .stencilAtt, .vertexBuffer, .indexBuffer, .vertexAttribute, .bufLink, .texLink, .passLink, .renderState => {},

                .bufSlot => |bufSlot| {
                    const bufPassId = bufSlot.bufLink.in;
                    if (renderGraph.share.bufClearPasses.isKeyUsed(bufPassId) and renderGraph.share.bufClearPasses.getByKey(bufPassId) == passId) {
                        const hardwareBufId = assigner.bufAssigns.getByKey(bufPassId);
                        bufBarrier(self, hardwareBufId, .Clear, .TransferWrite);
                        needsClearBarrier = true;
                    }
                },
                .texSlot => |texSlot| {
                    const texPassId = texSlot.texLink.in;
                    if (renderGraph.share.texClearPasses.isKeyUsed(texPassId) and renderGraph.share.texClearPasses.getByKey(texPassId) == passId) {
                        const hardwareTexId = assigner.texAssigns.getByKey(texPassId);
                        texBarrier(self, hardwareTexId, .Clear, .TransferWrite, .TransferDst, true); // Undefined Layout?
                        needsClearBarrier = true;
                    }
                },
            }
        }

        if (needsClearBarrier) try self.sortedNodes.append(.bakeBarriers);

        for (pass.passProperties.constSlice()) |attribute| {
            switch (attribute) {
                .shaderInf, .colorAtt, .depthAtt, .stencilAtt, .vertexBuffer, .indexBuffer, .vertexAttribute, .bufLink, .texLink, .passLink, .renderState => {},

                .bufSlot => |bufSlot| {
                    const bufPassId = bufSlot.bufLink.in;
                    if (renderGraph.share.bufClearPasses.isKeyUsed(bufPassId) and renderGraph.share.bufClearPasses.getByKey(bufPassId) == passId) {
                        const hardwareBufId = assigner.bufAssigns.getByKey(bufPassId);
                        clearBuffer(self, hardwareBufId);
                    }
                },
                .texSlot => |texSlot| {
                    const texPassId = texSlot.texLink.in;
                    if (renderGraph.share.texClearPasses.isKeyUsed(texPassId) and renderGraph.share.texClearPasses.getByKey(texPassId) == passId) {
                        const hardwareTexId = assigner.texAssigns.getByKey(texPassId);
                        clearTexture(self, hardwareTexId);
                    }
                },
            }
        }

        for (pass.passProperties.constSlice()) |attribute| {
            switch (attribute) {
                .shaderInf => |shaderInf| {
                    setShader(self, shaderInf.id);
                },
                .bufSlot => |bufSlot| {
                    const bufHardwareId = assigner.bufAssigns.getByKey(bufSlot.bufLink.in);
                    bufBarrier(self, bufHardwareId, bufSlot.stage, bufSlot.access);

                    if (bufSlot.shaderSlot) |slot| setPushDataBufDesc(self, pushOffset + (slot * @sizeOf(u32)), bufHardwareId);
                },
                .texSlot => |texSlot| {
                    const texHardwareId = assigner.texAssigns.getByKey(texSlot.texLink.in);
                    texBarrier(self, texHardwareId, texSlot.stage, texSlot.access, texSlot.layout, false);

                    if (texSlot.shaderSlot) |slot| setPushDataTexDesc(self, pushOffset + (slot * @sizeOf(u32)), texHardwareId, texSlot.descUse);
                },

                .colorAtt => |attSlot| {
                    const texPassId = attSlot.texLink.in;
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);

                    if (attSlot.clear) |clear| {
                        // Manually Set Clear
                        switch (clear) {
                            .color => |color| {
                                texBarrier(self, texHardwareId, attSlot.stage, attSlot.access, attSlot.layout, true);
                                setColorAtt(self, texHardwareId, color);
                            },
                            .depth => return error.ColorAttNeedsColorClear,
                        }
                    } else {
                        // Graph Clear through Attachment
                        if (renderGraph.share.texClearPasses.isKeyUsed(texPassId) and renderGraph.share.texClearPasses.getByKey(texPassId) == passId) {
                            texBarrier(self, texHardwareId, attSlot.stage, attSlot.access, attSlot.layout, true);
                            setColorAtt(self, texHardwareId, ClearColor{ .R = 0, .G = 0, .B = 0, .A = 0 });
                        } else {
                            texBarrier(self, texHardwareId, attSlot.stage, attSlot.access, attSlot.layout, false);
                            setColorAtt(self, texHardwareId, null);
                        }
                    }
                },
                .depthAtt => |depthSlot| {
                    const texPassId = depthSlot.texLink.in;
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);

                    if (depthSlot.clear) |clear| {
                        // Manually Set Clear
                        switch (clear) {
                            .depth => |depth| {
                                texBarrier(self, texHardwareId, depthSlot.stage, depthSlot.access, depthSlot.layout, true);
                                setDepthAtt(self, texHardwareId, depth);
                            },
                            .color => return error.DepthAttNeedsDepthClear,
                        }
                    } else {
                        // Graph Clear through Attachment
                        if (renderGraph.share.texClearPasses.isKeyUsed(texPassId) and renderGraph.share.texClearPasses.getByKey(texPassId) == passId) {
                            texBarrier(self, texHardwareId, depthSlot.stage, depthSlot.access, depthSlot.layout, true);
                            setDepthAtt(self, texHardwareId, ClearDepth{ .depthStencil = .{ .depth = 0, .stencil = 0 } });
                        } else {
                            texBarrier(self, texHardwareId, depthSlot.stage, depthSlot.access, depthSlot.layout, false);
                            setDepthAtt(self, texHardwareId, null);
                        }
                    }
                },
                .stencilAtt => |stencilSlot| {
                    const texPassId = stencilSlot.texLink.in;
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);

                    if (stencilSlot.clear) |clear| {
                        // Manually Set Clear
                        switch (clear) {
                            .depth => |depth| {
                                texBarrier(self, texHardwareId, stencilSlot.stage, stencilSlot.access, stencilSlot.layout, true);
                                setStencilAtt(self, texHardwareId, depth);
                            },
                            .color => return error.StencilAttNeedsDepthClear,
                        }
                    } else {
                        // Graph Clear through Attachment
                        if (renderGraph.share.texClearPasses.isKeyUsed(texPassId) and renderGraph.share.texClearPasses.getByKey(texPassId) == passId) {
                            texBarrier(self, texHardwareId, stencilSlot.stage, stencilSlot.access, stencilSlot.layout, true);
                            setStencilAtt(self, texHardwareId, ClearDepth{ .depthStencil = .{ .depth = 0, .stencil = 0 } });
                        } else {
                            texBarrier(self, texHardwareId, stencilSlot.stage, stencilSlot.access, stencilSlot.layout, false);
                            setStencilAtt(self, texHardwareId, null);
                        }
                    }
                },

                .vertexBuffer => |vertBufSlot| {
                    const bufHardwareId = assigner.bufAssigns.getByKey(vertBufSlot.bufPassId);
                    bufBarrier(self, bufHardwareId, .VertexInput, .VertexAttributeRead);
                    setVertexBuf(self, .{ .bufId = bufHardwareId, .binding = vertBufSlot.binding, .stride = vertBufSlot.stride, .inputRate = vertBufSlot.inputRate });
                },
                .indexBuffer => |indexBufSlot| {
                    const bufHardwareId = assigner.bufAssigns.getByKey(indexBufSlot.bufPassId);
                    bufBarrier(self, bufHardwareId, .VertexInput, .IndexRead);
                    setIndexBuf(self, .{ .bufId = bufHardwareId, .indexType = indexBufSlot.indexType });
                },
                .vertexAttribute => |vertAttrib| {
                    setVertexAttrib(self, vertAttrib);
                },
                .renderState => |stateChange| {
                    setRenderStateUnion(self, stateChange);
                },
                .bufLink, .texLink, .passLink => {},
            }
        }

        bakeBarriers(self);
        bindShaders(self);
        bindPushData(self);

        switch (pass.execution) {
            .compute => |comp| {
                if (comp.outputTexDispatch == true) {
                    if (mainOutputTexHardwareId) |outputTexId| {
                        dispatchOutputTex(self, comp.groupX, comp.groupY, comp.groupZ, outputTexId);
                    } else return error.outputTexDispatchHasNoMainOutput;
                } else dispatch(self, comp.groupX, comp.groupY, comp.groupZ);
            },
            .computeIndirect => |compIndirect| {
                const bufHardwareId = assigner.bufAssigns.getByKey(compIndirect.indirectBuf);
                dispatchIndirect(self, bufHardwareId, compIndirect.indirectBufOffset);
            },
            .vertex => |vertex| {
                bindRenderState(self);
                beginRendering(self);
                setViewportFromOutput(self);
                setScissorFromOutput(self);
                bindVertexInput(self);
                bindIndexInput(self);
                drawVertex(self, vertex);
                endRendering(self);
            },
            .vertexIndexed => |vertexIndexed| {
                bindRenderState(self);
                beginRendering(self);
                setViewportFromOutput(self);
                setScissorFromOutput(self);
                bindVertexInput(self);
                bindIndexInput(self);
                drawVertexIndexed(self, vertexIndexed);
                endRendering(self);
            },
            .taskOrMesh => |taskOrMesh| {
                bindRenderState(self);
                beginRendering(self);
                setViewportFromOutput(self);
                setScissorFromOutput(self);
                drawTaskOrMesh(self, taskOrMesh);
                endRendering(self);
            },
            .taskOrMeshIndirect => |taskOrMeshIndirect| {
                bindRenderState(self);
                beginRendering(self);
                setViewportFromOutput(self);
                setScissorFromOutput(self);

                const bufHardwareId = assigner.bufAssigns.getByKey(taskOrMeshIndirect.indirectBufId);
                drawTaskOrMeshIndirect(self, .{ .indirectBufId = bufHardwareId, .drawCount = 1, .bufOffset = taskOrMeshIndirect.bufOffset, .stride = @sizeOf(vhT.IndirectData) });

                endRendering(self);
            },
        }

        resetState(self);

        endTimer(self, timerId);
        endStats(self);
    }

    // String Spacers

    fn uiPrint(self: *RenderCompilerData, name: []const u8) !void {
        self.sortedNodes.appendAssumeCapacity(.{ .uiPrint = try .string(name) });
    }

    fn passPrint(self: *RenderCompilerData, name: []const u8) !void {
        self.sortedNodes.appendAssumeCapacity(.{ .passPrint = try .string(name) });
    }

    fn compositePrint(self: *RenderCompilerData, name: []const u8) !void {
        self.sortedNodes.appendAssumeCapacity(.{ .compositePrint = try .string(name) });
    }

    // Graph Commands

    fn clearBuffer(self: *RenderCompilerData, bufId: BufId) void {
        self.sortedNodes.appendAssumeCapacity(.{ .clearBuffer = bufId });
    }

    fn clearTexture(self: *RenderCompilerData, texId: TexId) void {
        self.sortedNodes.appendAssumeCapacity(.{ .clearTexture = texId });
    }

    // Barrier Commands
    fn recordTransfers(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.recordTransfers);
    }

    fn bufBarrier(self: *RenderCompilerData, bufId: BufId, stage: vhE.PipeStage, access: vhE.PipeAccess) void {
        const state = self.bufStates.getPtrByKey(bufId);
        const newState: BufferState = .{ .stage = stage, .access = access };
        self.sortedNodes.appendAssumeCapacity(.{ .bufBarrier = .{ .bufId = bufId, .oldState = state.*, .newState = newState } });
        state.* = newState;
    }

    fn texBarrier(self: *RenderCompilerData, texId: TexId, stage: vhE.PipeStage, access: vhE.PipeAccess, layout: vhE.ImageLayout, ignoreOld: bool) void {
        const state = self.texStates.getPtrByKey(texId);
        const newState: TextureState = .{ .stage = stage, .access = access, .layout = layout };
        self.sortedNodes.appendAssumeCapacity(.{ .texBarrier = .{ .texId = texId, .oldState = state.*, .newState = newState, .ignoreOld = ignoreOld } });
        state.* = newState;
    }

    fn swapchainTargetBarrier(self: *RenderCompilerData, windowId: WindowId, stage: vhE.PipeStage, access: vhE.PipeAccess, layout: vhE.ImageLayout) bool {
        const newState = TextureState{ .stage = stage, .access = access, .layout = layout };

        if (self.swapchainStates.isKeyUsed(windowId) == false) {
            const oldState = TextureState{ .layout = .Undefined, .stage = .ColorAtt, .access = .None };
            self.sortedNodes.appendAssumeCapacity(.{ .swapchainTargetBarrier = .{ .windowId = windowId, .oldState = oldState, .newState = newState, .ignoreOld = true } });
            self.swapchainStates.insert(windowId, newState);
            return true;
        } else {
            const state = self.swapchainStates.getPtrByKey(windowId);
            self.sortedNodes.appendAssumeCapacity(.{ .swapchainTargetBarrier = .{ .windowId = windowId, .oldState = state.*, .newState = newState, .ignoreOld = false } });
            state.* = newState;
            return false;
        }
    }

    fn bakeBarriers(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.bakeBarriers);
    }

    // Profiling Commands

    fn startTimer(self: *RenderCompilerData, name: []const u8, typ: QueryTyp) !u8 {
        const timerId = self.usedQueries;
        self.sortedNodes.appendAssumeCapacity(.{ .startTimer = .{ .name = try .string(name), .typ = typ, .pipeStage = .AllCmds, .queryId = timerId } });
        self.usedQueries += 1;
        return timerId;
    }

    fn endTimer(self: *RenderCompilerData, timerId: u8) void {
        self.sortedNodes.appendAssumeCapacity(.{ .endTimer = .{ .pipeStage = .BotOfPipe, .queryId = timerId } });
    }

    fn startStats(self: *RenderCompilerData, name: []const u8) !void {
        self.sortedNodes.appendAssumeCapacity(.{ .startStats = try .string(name) });
    }

    fn endStats(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.endStats);
    }

    // Pass Commands

    fn setShader(self: *RenderCompilerData, shaderId: ShaderId) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setShader = shaderId });
    }

    fn bindShaders(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.bindShaders);
    }

    fn setPushData(self: *RenderCompilerData, len: u8, offset: u32, dataBytes: []const u8) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setPushData = .{ .startIndex = self.pushData.len, .len = len, .offset = offset } });
        self.pushData.appendSliceAssumeCapacity(dataBytes);
    }

    fn setPushDataOutputExtent(self: *RenderCompilerData, offset: u32) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setPushDataOutputExtent = .{ .offset = offset } });
    }

    fn setPushDataBufDesc(self: *RenderCompilerData, offset: u32, bufId: BufId) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setPushDataBufDesc = .{ .bufId = bufId, .size = @sizeOf(u32), .offset = offset } });
    }

    fn setPushDataTexDesc(self: *RenderCompilerData, offset: u32, texId: TexId, descTyp: vhE.TexDescriptor) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setPushDataTexDesc = .{ .texId = texId, .size = @sizeOf(u32), .offset = offset, .descTyp = descTyp } });
    }

    fn bindPushData(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.bindPushData);
    }

    fn dispatch(self: *RenderCompilerData, groupX: u32, groupY: u32, groupZ: u32) void {
        self.sortedNodes.appendAssumeCapacity(.{ .dispatch = .{ .groupX = groupX, .groupY = groupY, .groupZ = groupZ } });
    }

    fn dispatchOutputTex(self: *RenderCompilerData, groupX: u32, groupY: u32, groupZ: u32, texId: TexId) void {
        self.sortedNodes.appendAssumeCapacity(.{ .dispatchOutputTex = .{ .groupX = groupX, .groupY = groupY, .groupZ = groupZ, .texId = texId } });
    }

    fn dispatchIndirect(self: *RenderCompilerData, indirectBufId: BufId, indirectBufOffset: u64) void {
        self.sortedNodes.appendAssumeCapacity(.{ .dispatchIndirect = .{ .indirectBufId = indirectBufId, .indirectBufOffset = indirectBufOffset } });
    }

    fn setOutputExtentSwapchain(self: *RenderCompilerData, windowId: WindowId) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setOutputExtentSwapchain = windowId });
    }

    fn setOutputExtent(self: *RenderCompilerData, texId: ?TexId) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setOutputExtent = texId });
    }

    // Draw Commands

    fn beginRendering(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.beginRendering);
    }

    fn setViewport(self: *RenderCompilerData, x: f32, y: f32, width: f32, height: f32) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setViewport = .{ .x = x, .y = y, .width = width, .height = height } });
    }

    fn setViewportFromTex(self: *RenderCompilerData, texId: TexId) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setViewportFromTex = texId });
    }

    fn setViewportFromOutput(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.setViewportFromOutput);
    }

    fn setScissor(self: *RenderCompilerData, x: f32, y: f32, width: f32, height: f32) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setScissor = .{ .x = x, .y = y, .width = width, .height = height } });
    }

    fn setScissorFromTex(self: *RenderCompilerData, texId: TexId) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setScissorFromTex = texId });
    }

    fn setScissorFromOutput(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.setScissorFromOutput);
    }

    fn setRenderStateUnion(self: *RenderCompilerData, renderStateUnion: RenderStateUnion) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = renderStateUnion });
    }

    fn bindRenderState(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.bindRenderState);
    }

    fn setColorAttSwapchain(self: *RenderCompilerData, windowId: WindowId, firstUse: bool) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setColorAttSwapchain = .{ .windowId = windowId, .firstUse = firstUse } });
    }

    fn setColorAtt(self: *RenderCompilerData, texId: TexId, clear: ?ClearColor) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setColorAtt = .{ .texId = texId, .clear = clear } });
    }

    fn setDepthAtt(self: *RenderCompilerData, texId: TexId, clear: ?ClearDepth) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setDepthAtt = .{ .texId = texId, .clear = clear } });
    }

    fn setStencilAtt(self: *RenderCompilerData, texId: TexId, clear: ?ClearDepth) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setStencilAtt = .{ .texId = texId, .clear = clear } });
    }

    fn setIndexBuf(self: *RenderCompilerData, indexBufferUse: IndexBufferUse) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setIndexBuf = indexBufferUse });
    }

    fn bindIndexInput(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.bindIndexInput);
    }

    fn setVertexBuf(self: *RenderCompilerData, vertexBufferUse: VertexBufferUse) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setVertexBuf = vertexBufferUse });
    }

    fn setVertexAttrib(self: *RenderCompilerData, vertexAttribute: VertexAttribute) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setVertexAttrib = vertexAttribute });
    }

    fn bindVertexInput(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.bindVertexInput);
    }

    fn drawVertex(self: *RenderCompilerData, vertexExec: VertexExec) void {
        self.sortedNodes.appendAssumeCapacity(.{ .drawVertex = vertexExec });
    }

    fn drawVertexIndexed(self: *RenderCompilerData, vertexIndexedExec: VertexIndexedExec) void {
        self.sortedNodes.appendAssumeCapacity(.{ .drawVertexIndexed = vertexIndexedExec });
    }

    fn drawTaskOrMesh(self: *RenderCompilerData, taskOrMeshExec: TaskOrMeshExec) void {
        self.sortedNodes.appendAssumeCapacity(.{ .drawTaskOrMesh = taskOrMeshExec });
    }

    fn drawTaskOrMeshIndirect(self: *RenderCompilerData, taskOrMeshIndirectExec: TaskOrMeshIndirectExec) void {
        self.sortedNodes.appendAssumeCapacity(.{ .drawTaskOrMeshIndirect = taskOrMeshIndirectExec });
    }

    fn endRendering(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.endRendering);
    }

    fn resetState(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.resetState);
    }
};
