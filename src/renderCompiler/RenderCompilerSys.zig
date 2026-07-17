const RenderAssignerData = @import("../renderAssigner/RenderAssignerData.zig").RenderAssignerData;
const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const RenderGraphData = @import("../renderGraph/RenderGraphData.zig").RenderGraphData;
const RenderCompilerData = @import("RenderCompilerData.zig").RenderCompilerData;
const sc = @import("../.configs/shaderConfig.zig");
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

const vk = @import("../.modules/vk.zig").c;
const vhE = @import("../render/help/Enums.zig");

const TaskOrMeshIndirectExec = @import("../render/types/pass/PassDefinition.zig").TaskOrMeshIndirectExec;
const ComputeIndirectExec = @import("../render/types/pass/PassDefinition.zig").ComputeIndirectExec;
const VertexIndexedExec = @import("../render/types/pass/PassDefinition.zig").VertexIndexedExec;
const TaskOrMeshExec = @import("../render/types/pass/PassDefinition.zig").TaskOrMeshExec;
const VertexExec = @import("../render/types/pass/PassDefinition.zig").VertexExec;
const VertexBufferFill = @import("../render/types/pass/VertexBufferUse.zig").VertexBufferFill;
const IndexBufferFill = @import("../render/types/pass/IndexBufferUse.zig").IndexBufferFill;
const VertexAttribute = @import("../render/types/pass/VertexAttribute.zig").VertexAttribute;
const AttachmentFill = @import("../render/types/pass/AttachmentUse.zig").AttachmentFill;
const ClearColor = @import("../render/types/pass/AttachmentUse.zig").ClearColor;
const ClearDepth = @import("../render/types/pass/AttachmentUse.zig").ClearDepth;
const RenderState = @import("../render/types/pass/RenderState.zig").RenderState;
const RenderStateUnion = @import("../render/types/pass/RenderState.zig").RenderStateUnion;
const TextureFill = @import("../render/types/pass/TextureUse.zig").TextureFill;
const RenderNode = @import("../render/types/pass/RenderNode.zig").RenderNode;
const BufferFill = @import("../render/types/pass/BufferUse.zig").BufferFill;
const WindowData = @import("../window/WindowData.zig").WindowData;
const WindowId = @import("../.configs/idConfig.zig").WindowId;
const ShaderId = @import("../.configs/idConfig.zig").ShaderId;
const PassId = @import("../.configs/idConfig.zig").PassId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const TexId = @import("../.configs/idConfig.zig").TexId;
const UiData = @import("../ui/UiData.zig").UiData;

const QueryTyp = @import("../render/types/base/Cmd.zig").QueryPair.QueryTyp;
const CompositeNode = @import("../render/types/pass/RenderNode.zig").CompositeNode;
const vhT = @import("../render/help/Types.zig");

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
        self.sortedNodes.clear();
        self.pushData.clear();
        self.usedQueries = 0;

        for (renderGraph.sorter.sortedRenderIR.constSlice()) |IR| {
            switch (IR) {
                // .uiIR => |uiIR| {},
                .compositeIR => |compositeIR| {
                    var compositeCopy = compositeIR;

                    switch (compositeCopy.srcTexUnion) {
                        .texName => |name| {
                            const texPassId = try registry.getTexturePassId(name);
                            const hardwareTexId = assigner.texAssigns.getByKey(texPassId);
                            compositeCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texPassId => |texPassId| {
                            const hardwareTexId = assigner.texAssigns.getByKey(texPassId);
                            compositeCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texId => {},
                    }
                    try fillCompositePassHardwareIdCmds(self, assigner, registry, compositeCopy);
                },
                .passIR => |passIR| {
                    try fillPassHardwareIdCmds(self, assigner, registry, renderGraph, passIR, runTime, deltaTime);
                },
                .clearBufIR => |clearBufIR| {
                    const hardwareTexId = assigner.bufAssigns.getByKey(clearBufIR);
                    try self.sortedNodes.append(.{ .clearBuffer = hardwareTexId });
                },
                .clearTexIR => |clearTexIR| {
                    const hardwareTexId = assigner.texAssigns.getByKey(clearTexIR);
                    try self.sortedNodes.append(.{ .clearTexture = hardwareTexId });
                },
                .barrierBakeClears => |barrierBakeClears| {
                    try self.sortedNodes.append(.{ .barrierBakeClears = barrierBakeClears });
                },
            }
        }

        // Build UI Passes
        try fillUiPassHardwareIdCmds(self, assigner, registry, uiData, windowData);

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
                    .barrierBakeClears => std.debug.print("- {}. Bake Clears\n", .{index}),

                    // OTHER COMMAND IN STREAM
                    inline else => |_, tag| std.debug.print("- {}. {s}\n", .{ index, @tagName(tag) }),
                }
            }
            std.debug.print("\n", .{});
        }
    }

    fn fillCompositePassHardwareIdCmds(self: *RenderCompilerData, _: *const RenderAssignerData, _: *const RenderRegistryData, composite: CompositeNode) !void {
        if (composite.srcTexUnion != .texId) return error.CompositSrcTexIdIsNotHardwareId;

        try compositePrint(self, composite.name);
        const timerId = try startTimer(self, composite.name, .Composite);

        setColorAttSwapchain(self, composite.windowId);
        setOutputExtentSwapchain(self, composite.windowId);

        // Barriers
        swapchainTargetBarrier(self, composite.windowId, .ColorAtt, .ColorAttReadWrite, .Attachment);
        texBarrier(self, composite.srcTexUnion.texId, .Fragment, .SampledRead, .General);
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
        setPushDataTexDesc(self, 0 * @sizeOf(u32), composite.srcTexUnion.texId, .Sampled);
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

    fn fillUiPassHardwareIdCmds(self: *RenderCompilerData, _: *const RenderAssignerData, _: *const RenderRegistryData, uiData: *const UiData, windowData: *const WindowData) !void {
        for (uiData.uiNodes.constSlice()) |uiNode| {
            if (windowData.windows.isKeyUsed(uiNode.windowId.val()) == false) return error.UiRenderCompileCantFindWindowId;
            if (uiNode.imguiVB != .bufId) return error.UiNodeImguiVBIsNotHardwareId;
            if (uiNode.imguiIB != .bufId) return error.UiNodeImguiVBIsNotHardwareId;

            try uiPrint(self, uiNode.name);

            const timerId = try startTimer(self, uiNode.name, .Ui);

            const uiDrawList = uiData.uiDraws.constSlice()[uiNode.firstDrawIndex..uiNode.lastDrawIndex];

            setColorAttSwapchain(self, uiNode.windowId);
            setOutputExtentSwapchain(self, uiNode.windowId);

            // Barriers:
            swapchainTargetBarrier(self, uiNode.windowId, .ColorAtt, .ColorAttReadWrite, .Attachment);
            bufBarrier(self, uiNode.imguiVB.bufId, .VertexInput, .VertexAttributeRead);
            bufBarrier(self, uiNode.imguiIB.bufId, .VertexInput, .IndexRead);

            for (uiDrawList) |uiDraw| {
                if (uiDraw.drawTex != .texId) return error.UiDrawTexIsNoHardwareId;
                texBarrier(self, uiDraw.drawTex.texId, .Fragment, .SampledRead, .General);
                break; // CURRENTLY ONLY DOING ONE TEXTURE FOR UI, HAS TO BE FIXED IF MORE TEXTURES ARE USED!!;
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

            setVertexBuf(self, .{ .bufId = uiNode.imguiVB.bufId, .binding = 0, .stride = 20, .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX });

            setVertexAttrib(self, .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 0 });
            setVertexAttrib(self, .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 8 });
            setVertexAttrib(self, .{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = 16 });
            bindVertexInput(self);

            setIndexBuf(self, .{ .bufId = uiNode.imguiIB.bufId, .indexType = vk.VK_INDEX_TYPE_UINT16 });
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

                // const texPassId = try registry.getTexturePassId(uiDraw.drawTex);
                // const texHardwareId = assigner.texAssigns.getByKey(uiDraw.drawTex.texId);
                setPushDataTexDesc(self, (4 * @sizeOf(u32)), uiDraw.drawTex.texId, .Sampled);

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
        _: *const RenderGraphData,
        passId: PassId,
        runTime: f32,
        deltaTime: f32,
    ) !void {
        const passName = try registry.getPassName(passId);
        const passDef = try registry.getPassDefinition(passName);
        const mainOutputTexId = if (passDef.outputTex) |output| try registry.getTexturePassId(output) else null;
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

        for (passDef.passAttribute.constSlice()) |attribute| {
            switch (attribute) {
                .shaderInf => |shaderInf| {
                    setShader(self, shaderInf.id);
                },
                .bufSlot => |bufSlot| {
                    const bufPassId = try registry.getBufferPassId(bufSlot.bufLink.in);
                    const bufHardwareId = assigner.bufAssigns.getByKey(bufPassId);
                    bufBarrier(self, bufHardwareId, bufSlot.stage, bufSlot.access);

                    if (bufSlot.shaderSlot) |slot| setPushDataBufDesc(self, pushOffset + (slot * @sizeOf(u32)), bufHardwareId);
                },
                .texSlot => |texSlot| {
                    const texPassId = try registry.getTexturePassId(texSlot.texLink.in);
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);
                    texBarrier(self, texHardwareId, texSlot.stage, texSlot.access, texSlot.layout);

                    if (texSlot.shaderSlot) |slot| setPushDataTexDesc(self, pushOffset + (slot * @sizeOf(u32)), texHardwareId, texSlot.descUse);
                },
                .colorAtt => |attSlot| {
                    const texPassId = try registry.getTexturePassId(attSlot.texLink.in);
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);
                    texBarrier(self, texHardwareId, attSlot.stage, attSlot.access, attSlot.layout);

                    if (attSlot.clear != null and attSlot.clear.? != .color) return error.ColorAttNeedsColorClear;
                    setColorAtt(self, texHardwareId, if (attSlot.clear) |clear| clear.color else null);
                },
                .depthAtt => |depthSlot| {
                    const texPassId = try registry.getTexturePassId(depthSlot.texLink.in);
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);
                    texBarrier(self, texHardwareId, depthSlot.stage, depthSlot.access, depthSlot.layout);

                    if (depthSlot.clear != null and depthSlot.clear.? != .depth) return error.DepthAttNeedsDepthClear;
                    setDepthAtt(self, texHardwareId, if (depthSlot.clear) |clear| clear.depth else null);
                },
                .stencilAtt => |stencilSlot| {
                    const texPassId = try registry.getTexturePassId(stencilSlot.texLink.in);
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);
                    texBarrier(self, texHardwareId, stencilSlot.stage, stencilSlot.access, stencilSlot.layout);

                    if (stencilSlot.clear != null and stencilSlot.clear.? != .depth) return error.StencilAttNeedsDepthClear;
                    setStencilAtt(self, texHardwareId, if (stencilSlot.clear) |clear| clear.depth else null);
                },
                .vertexBuffer => |vertBufSlot| {
                    const bufPassId = try registry.getBufferPassId(vertBufSlot.bufInput);
                    const bufHardwareId = assigner.bufAssigns.getByKey(bufPassId);
                    bufBarrier(self, bufHardwareId, .VertexInput, .VertexAttributeRead);
                    setVertexBuf(self, .{ .bufId = bufHardwareId, .binding = vertBufSlot.binding, .stride = vertBufSlot.stride, .inputRate = vertBufSlot.inputRate });
                },
                .indexBuffer => |indexBufSlot| {
                    const bufPassId = try registry.getBufferPassId(indexBufSlot.bufInput);
                    const bufHardwareId = assigner.bufAssigns.getByKey(bufPassId);
                    bufBarrier(self, bufHardwareId, .VertexInput, .IndexRead);
                    setIndexBuf(self, .{ .bufId = bufHardwareId, .indexType = indexBufSlot.indexType });
                },
                .vertexAttribute => |vertAttrib| {
                    setVertexAttrib(self, vertAttrib);
                },
                .renderState => |stateChange| {
                    setRenderStateUnion(self, stateChange);
                },
                .bufLinking, .texLinking => {},
            }
        }

        bakeBarriers(self);
        bindShaders(self);
        bindPushData(self);

        switch (passDef.execution) {
            .compute => |comp| {
                if (comp.outputTexDispatch == true) {
                    if (mainOutputTexHardwareId) |outputTexId| {
                        dispatchOutputTex(self, comp.groupX, comp.groupY, comp.groupZ, outputTexId);
                    } else return error.outputTexDispatchHasNoMainOutput;
                } else dispatch(self, comp.groupX, comp.groupY, comp.groupZ);
            },
            .computeIndirect => |compIndirect| {
                const bufPassId = try registry.getBufferPassId(compIndirect.indirectBuf);
                const bufHardwareId = assigner.bufAssigns.getByKey(bufPassId);
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

                const bufPassId = try registry.getBufferPassId(taskOrMeshIndirect.indirectBuf);
                const bufHardwareId = assigner.bufAssigns.getByKey(bufPassId);
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

    fn bakeClearBarriers(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.barrierBakeClears);
    }

    // Barrier Commands

    fn bufBarrier(self: *RenderCompilerData, bufId: BufId, stage: vhE.PipeStage, access: vhE.PipeAccess) void {
        self.sortedNodes.appendAssumeCapacity(.{ .bufBarrier = .{ .bufId = bufId, .stage = stage, .access = access } });
    }

    fn texBarrier(self: *RenderCompilerData, texId: TexId, stage: vhE.PipeStage, access: vhE.PipeAccess, layout: vhE.ImageLayout) void {
        self.sortedNodes.appendAssumeCapacity(.{ .texBarrier = .{ .texId = texId, .stage = stage, .access = access, .layout = layout } });
    }

    fn swapchainTargetBarrier(self: *RenderCompilerData, windowId: WindowId, stage: vhE.PipeStage, access: vhE.PipeAccess, layout: vhE.ImageLayout) void {
        self.sortedNodes.appendAssumeCapacity(.{ .swapchainTargetBarrier = .{ .windowId = windowId, .stage = stage, .access = access, .layout = layout } });
    }

    fn bakeBarriers(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.bakeBarriers);
    }

    // Profiling Commands

    fn startTimer(self: *RenderCompilerData, name: []const u8, typ: QueryTyp) !u8 {
        const timerId = self.usedQueries;
        self.sortedNodes.appendAssumeCapacity(.{ .startTimer = .{ .name = try .string(name), .typ = typ, .pipeStage = .TopOfPipe, .queryId = timerId } });
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

    fn setColorAttSwapchain(self: *RenderCompilerData, windowId: WindowId) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setColorAttSwapchain = windowId });
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

    fn setIndexBuf(self: *RenderCompilerData, indexBufferFill: IndexBufferFill) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setIndexBuf = indexBufferFill });
    }

    fn bindIndexInput(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.bindIndexInput);
    }

    fn setVertexBuf(self: *RenderCompilerData, vertexBufferFill: VertexBufferFill) void {
        self.sortedNodes.appendAssumeCapacity(.{ .setVertexBuf = vertexBufferFill });
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
