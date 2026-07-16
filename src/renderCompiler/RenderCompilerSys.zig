const RenderAssignerData = @import("../renderAssigner/RenderAssignerData.zig").RenderAssignerData;
const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const RenderGraphData = @import("../renderGraph/RenderGraphData.zig").RenderGraphData;
const RenderCompilerData = @import("RenderCompilerData.zig").RenderCompilerData;
const sc = @import("../.configs/shaderConfig.zig");
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

const vk = @import("../.modules/vk.zig").c;

const CompositePushData = @import("../render/help/Types.zig").CompositePushData;
const ImGuiPushConstants = @import("../render/help/Types.zig").ImGuiPushConstants;

const TaskOrMeshIndirectExec = @import("../render/types/pass/PassInstance.zig").TaskOrMeshIndirectExec;
const ComputeIndirectExec = @import("../render/types/pass/PassInstance.zig").ComputeIndirectExec;
const VertexBufferFill = @import("../render/types/pass/VertexBufferFill.zig").VertexBufferFill;
const IndexBufferFill = @import("../render/types/pass/IndexBufferFill.zig").IndexBufferFill;
const VertexAttribute = @import("../render/types/pass/VertexAttribute.zig").VertexAttribute;
const AttachmentFill = @import("../render/types/pass/AttachmentFill.zig").AttachmentFill;
const TextureFill = @import("../render/types/pass/TextureFill.zig").TextureFill;
const RenderState = @import("../render/types/pass/RenderState.zig").RenderState;
const BufferFill = @import("../render/types/pass/BufferFill.zig").BufferFill;
const RenderNode = @import("../render/types/pass/RenderNode.zig").RenderNode;
const WindowData = @import("../window/WindowData.zig").WindowData;
const PassId = @import("../.configs/idConfig.zig").PassId;
const UiData = @import("../ui/UiData.zig").UiData;

const QueryTyp = @import("../render/types/base/Cmd.zig").QueryPair.QueryTyp;
const CompositeNode = @import("../render/types/pass/RenderNode.zig").CompositeNode;
const vhT = @import("../render/help/Types.zig");

pub const RenderCompilerSys = struct {
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
        self.sortedNodes.appendAssumeCapacity(.{ .startStats = .{ .name = try .string(name) } });
    }

    fn endStats(self: *RenderCompilerData) void {
        self.sortedNodes.appendAssumeCapacity(.endStats);
    }

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

                    // COMMAND STREAM
                    inline else => |_, tag| std.debug.print("- {}. {s}\n", .{ index, @tagName(tag) }),
                }
            }
            std.debug.print("\n", .{});
        }
    }

    fn fillCompositePassHardwareIdCmds(self: *RenderCompilerData, _: *const RenderAssignerData, _: *const RenderRegistryData, composite: CompositeNode) !void {
        if (composite.srcTexUnion != .texId) return error.CompositSrcTexIdIsNotHardwareId;

        self.sortedNodes.appendAssumeCapacity(.{ .compositePrint = try .string(composite.name) });
        const timerId = try startTimer(self, composite.name, .Composite);

        self.sortedNodes.appendAssumeCapacity(.{ .setColorAttSwapchain = .{ .windowId = composite.windowId } });
        self.sortedNodes.appendAssumeCapacity(.{ .setOutputExtentSwapchain = .{ .windowId = composite.windowId } });

        // Barriers
        self.sortedNodes.appendAssumeCapacity(.{ .swapchainTargetBarrier = .{ .windowId = composite.windowId, .stage = .ColorAtt, .access = .ColorAttReadWrite, .layout = .Attachment } });
        self.sortedNodes.appendAssumeCapacity(.{ .texBarrier = .{ .texId = composite.srcTexUnion.texId, .stage = .Fragment, .access = .SampledRead, .layout = .General } });
        self.sortedNodes.appendAssumeCapacity(.bakeBarriers);

        // Shaders
        self.sortedNodes.appendAssumeCapacity(.{ .setShader = sc.compositeFrag.id });
        self.sortedNodes.appendAssumeCapacity(.{ .setShader = sc.compositeVert.id });
        self.sortedNodes.appendAssumeCapacity(.bindShaders);

        const x: f32 = @floatFromInt(composite.viewOffsetX);
        const y: f32 = @floatFromInt(composite.viewOffsetY);
        const viewWidth: f32 = @floatFromInt(composite.viewWidth);
        const viewHeight: f32 = @floatFromInt(composite.viewHeight);
        self.sortedNodes.appendAssumeCapacity(.{ .setScissor = .{ .x = x, .y = y, .width = viewWidth, .height = viewHeight } });
        self.sortedNodes.appendAssumeCapacity(.{ .setViewport = .{ .x = x, .y = y, .width = viewWidth, .height = viewHeight } });

        // Push Constants
        // const texPassId = try registry.getTexturePassId(drawTex);
        // const texHardwareId = assigner.texAssigns.getByKey(drawTex.texId);
        self.sortedNodes.appendAssumeCapacity(.{ .setPushDataTexDesc = .{ .texId = composite.srcTexUnion.texId, .size = @sizeOf(u32), .offset = 0, .descTyp = .Sampled } });
        self.sortedNodes.appendAssumeCapacity(.{ .setPushData = .{ .startIndex = self.pushData.len, .len = (5 * @sizeOf(u32)), .offset = @sizeOf(u32) } });
        self.pushData.appendSliceAssumeCapacity(std.mem.asBytes(&rc.SAMPLER_LINEAR_CLAMP_INDEX));
        const stretch: u32 = if (composite.stretch) 1 else 0;
        self.pushData.appendSliceAssumeCapacity(std.mem.asBytes(&stretch));
        self.pushData.appendSliceAssumeCapacity(std.mem.asBytes(&composite.opacity));
        self.pushData.appendSliceAssumeCapacity(std.mem.asBytes(&composite.viewWidth));
        self.pushData.appendSliceAssumeCapacity(std.mem.asBytes(&composite.viewHeight));

        self.sortedNodes.appendAssumeCapacity(.bindPushData);

        // Render State
        self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = .{ .colorBlend = .True } });
        self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = .{
            .colorBlendEquation = .{
                .srcColor = .SrcAlpha,
                .dstColor = .OneMinusSrcAlpha,
                .colorOperation = .Add,
                .srcAlpha = .One,
                .dstAlpha = .OneMinusSrcAlpha,
                .alphaOperation = .Add,
            },
        } });
        self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = .{ .depthTest = .False } });
        self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = .{ .depthWrite = .False } });
        self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = .{ .cullMode = .None } });

        self.sortedNodes.appendAssumeCapacity(.bindRenderState);

        // Rendering
        self.sortedNodes.appendAssumeCapacity(.beginRendering);
        self.sortedNodes.appendAssumeCapacity(.bindVertexInput);
        self.sortedNodes.appendAssumeCapacity(.bindIndexInput); // Is this needed?
        self.sortedNodes.appendAssumeCapacity(.{ .drawVertex = .{ .vertexCount = 3, .instanceCount = 1, .firstVertex = 0, .firstInstance = 0 } });
        self.sortedNodes.appendAssumeCapacity(.endRendering);

        self.sortedNodes.appendAssumeCapacity(.resetState);

        endTimer(self, timerId);
    }

    fn fillUiPassHardwareIdCmds(self: *RenderCompilerData, _: *const RenderAssignerData, _: *const RenderRegistryData, uiData: *const UiData, windowData: *const WindowData) !void {
        for (uiData.uiNodes.constSlice()) |uiNode| {
            if (windowData.windows.isKeyUsed(uiNode.windowId.val()) == false) return error.UiRenderCompileCantFindWindowId;
            if (uiNode.imguiVB != .bufId) return error.UiNodeImguiVBIsNotHardwareId;
            if (uiNode.imguiIB != .bufId) return error.UiNodeImguiVBIsNotHardwareId;

            self.sortedNodes.appendAssumeCapacity(.{ .uiPrint = try .string(uiNode.name) });
            const timerId = try startTimer(self, uiNode.name, .Ui);

            const uiDrawList = uiData.uiDraws.constSlice()[uiNode.firstDrawIndex..uiNode.lastDrawIndex];

            self.sortedNodes.appendAssumeCapacity(.{ .setColorAttSwapchain = .{ .windowId = uiNode.windowId } });
            self.sortedNodes.appendAssumeCapacity(.{ .setOutputExtentSwapchain = .{ .windowId = uiNode.windowId } });

            // Barriers:
            self.sortedNodes.appendAssumeCapacity(.{ .swapchainTargetBarrier = .{ .windowId = uiNode.windowId, .stage = .ColorAtt, .access = .ColorAttReadWrite, .layout = .Attachment } });
            self.sortedNodes.appendAssumeCapacity(.{ .bufBarrier = .{ .bufId = uiNode.imguiVB.bufId, .stage = .VertexInput, .access = .VertexAttributeRead } });
            self.sortedNodes.appendAssumeCapacity(.{ .bufBarrier = .{ .bufId = uiNode.imguiIB.bufId, .stage = .VertexInput, .access = .IndexRead } });

            for (uiDrawList) |uiDraw| {
                if (uiDraw.drawTex != .texId) return error.UiDrawTexIsNoHardwareId;
                self.sortedNodes.appendAssumeCapacity(.{ .texBarrier = .{ .texId = uiDraw.drawTex.texId, .stage = .Fragment, .access = .SampledRead, .layout = .General } });
                break; // CURRENTLY ONLY DOING ONE TEXTURE FOR UI, HAS TO BE FIXED IF MORE TEXTURES ARE USED!!;
            }

            self.sortedNodes.appendAssumeCapacity(.bakeBarriers);

            self.sortedNodes.appendAssumeCapacity(.{ .setShader = sc.imguiVert.id });
            self.sortedNodes.appendAssumeCapacity(.{ .setShader = sc.imguiFrag.id });
            self.sortedNodes.appendAssumeCapacity(.bindShaders);

            // Render State
            self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = .{ .cullMode = .None } });
            self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = .{ .depthTest = .False } });
            self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = .{ .depthWrite = .False } });
            self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = .{ .colorBlend = .True } });
            self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = .{
                .colorBlendEquation = .{
                    .srcColor = .SrcAlpha,
                    .dstColor = .OneMinusSrcAlpha,
                    .colorOperation = .Add,
                    .srcAlpha = .One,
                    .dstAlpha = .OneMinusSrcAlpha,
                    .alphaOperation = .Add,
                },
            } });
            self.sortedNodes.appendAssumeCapacity(.bindRenderState);

            // Rendering
            self.sortedNodes.appendAssumeCapacity(.beginRendering);

            self.sortedNodes.appendAssumeCapacity(.setViewportFromOutput);

            self.sortedNodes.appendAssumeCapacity(.{ .setVertexBuf = .{ .vertexBuffer = .{
                .bufId = uiNode.imguiVB.bufId,
                .binding = 0,
                .stride = 20,
                .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
            } } });

            self.sortedNodes.appendAssumeCapacity(.{ .setVertexAttrib = .{ .vertexAttribute = .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 0 } } });
            self.sortedNodes.appendAssumeCapacity(.{ .setVertexAttrib = .{ .vertexAttribute = .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 8 } } });
            self.sortedNodes.appendAssumeCapacity(.{ .setVertexAttrib = .{ .vertexAttribute = .{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = 16 } } });
            self.sortedNodes.appendAssumeCapacity(.bindVertexInput);

            self.sortedNodes.appendAssumeCapacity(.{ .setIndexBuf = .{ .indexBuffer = .{ .bufId = uiNode.imguiIB.bufId, .indexType = vk.VK_INDEX_TYPE_UINT16 } } });
            self.sortedNodes.appendAssumeCapacity(.bindIndexInput);

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

                self.sortedNodes.appendAssumeCapacity(.{ .setScissor = .{ .x = x0, .y = y0, .width = x1 - x0, .height = y1 - y0 } });

                const drawTex = uiDraw.drawTex;

                self.sortedNodes.appendAssumeCapacity(.{ .setPushData = .{ .startIndex = self.pushData.len, .len = (4 * @sizeOf(u32)), .offset = 0 } });
                self.pushData.appendSliceAssumeCapacity(std.mem.asBytes(&scaleX));
                self.pushData.appendSliceAssumeCapacity(std.mem.asBytes(&scaleY));
                self.pushData.appendSliceAssumeCapacity(std.mem.asBytes(&translateX));
                self.pushData.appendSliceAssumeCapacity(std.mem.asBytes(&translateY));

                // const texPassId = try registry.getTexturePassId(drawTex);
                // const texHardwareId = assigner.texAssigns.getByKey(drawTex.texId);
                self.sortedNodes.appendAssumeCapacity(.{ .setPushDataTexDesc = .{ .texId = drawTex.texId, .size = @sizeOf(u32), .offset = (4 * @sizeOf(u32)), .descTyp = .Sampled } });

                self.sortedNodes.appendAssumeCapacity(.bindPushData);

                self.sortedNodes.appendAssumeCapacity(.{ .drawVertexIndexed = .{
                    .indexCount = uiDraw.elemCount,
                    .instanceCount = 1,
                    .firstIndex = uiDraw.idxOffset,
                    .vertexOffset = uiDraw.vtxOffset,
                    .firstInstance = 0,
                } });
            }

            self.sortedNodes.appendAssumeCapacity(.endRendering);
            self.sortedNodes.appendAssumeCapacity(.resetState);

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

        self.sortedNodes.appendAssumeCapacity(.{ .passPrint = try .string(passName) });
        const timerId = try startTimer(self, passName, .Pass);
        try startStats(self, passName);

        self.sortedNodes.appendAssumeCapacity(.{ .setOutputExtent = .{ .mainOutput = mainOutputTexHardwareId } });

        var pushOffset: u32 = 0;

        self.sortedNodes.appendAssumeCapacity(.{ .setPushData = .{ .startIndex = self.pushData.len, .len = (1 * @sizeOf(u32)), .offset = pushOffset } });
        self.pushData.appendSliceAssumeCapacity(std.mem.asBytes(&runTime));
        pushOffset += @sizeOf(f32);

        self.sortedNodes.appendAssumeCapacity(.{ .setPushData = .{ .startIndex = self.pushData.len, .len = (1 * @sizeOf(u32)), .offset = pushOffset } });
        self.pushData.appendSliceAssumeCapacity(std.mem.asBytes(&deltaTime));
        pushOffset += @sizeOf(f32);

        self.sortedNodes.appendAssumeCapacity(.{ .setPushDataOutputExtent = .{ .offset = pushOffset } });
        pushOffset += @sizeOf(f32) + @sizeOf(f32);

        var execution: RenderNode = undefined;

        for (passDef.passAttribute.constSlice()) |attribute| {
            switch (attribute) {
                .execution => |exec| {
                    switch (exec) {
                        .compute => |comp| {
                            if (comp.outputTexDispatch == true) {
                                if (mainOutputTexHardwareId) |outputTexId| {
                                    execution = .{ .dispatchImg = .{ .groupX = comp.groupX, .groupY = comp.groupY, .groupZ = comp.groupZ, .img = outputTexId } };
                                } else return error.outputTexDispatchHasNoMainOutput;
                            } else execution = .{ .dispatch = .{ .groupX = comp.groupX, .groupY = comp.groupY, .groupZ = comp.groupZ } };
                        },
                        .taskOrMesh => |taskOrMesh| {
                            execution = .{ .drawTaskOrMesh = .{ .groupX = taskOrMesh.groupX, .groupY = taskOrMesh.groupY, .groupZ = taskOrMesh.groupZ } };
                        },
                        .vertex => |vertex| {
                            execution = .{ .drawVertex = .{ .vertexCount = vertex.vertices, .instanceCount = vertex.instances, .firstVertex = 0, .firstInstance = 0 } };
                        },
                        .vertexIndexed => |vertexIndexed| {
                            execution = .{ .drawVertexIndexed = .{
                                .indexCount = vertexIndexed.indexCount,
                                .instanceCount = vertexIndexed.instanceCount,
                                .firstIndex = vertexIndexed.firstIndex,
                                .vertexOffset = vertexIndexed.vertexOffset,
                                .firstInstance = vertexIndexed.firstInstance,
                            } };
                        },
                        .computeIndirect => |compIndirect| {
                            const bufPassId = try registry.getBufferPassId(compIndirect.indirectBuf);
                            const bufHardwareId = assigner.bufAssigns.getByKey(bufPassId);
                            execution = .{ .dispatchIndirect = .{ .indirectBufId = bufHardwareId, .indirectBufOffset = compIndirect.indirectBufOffset } };
                        },
                        .taskOrMeshIndirect => |taskOrMeshIndirect| {
                            const bufPassId = try registry.getBufferPassId(taskOrMeshIndirect.indirectBuf);
                            const bufHardwareId = assigner.bufAssigns.getByKey(bufPassId);
                            execution = .{ .drawTaskOrMeshIndirect = .{
                                .indirectBufId = bufHardwareId,
                                .drawCount = 1,
                                .offset = taskOrMeshIndirect.indirectBufOffset,
                                .stride = @sizeOf(vhT.IndirectData),
                            } };
                        },
                    }
                },
                .shaderInf => |shaderInf| {
                    self.sortedNodes.appendAssumeCapacity(.{ .setShader = shaderInf.id });
                },
                .bufSlot => |bufSlot| {
                    const bufPassId = try registry.getBufferPassId(bufSlot.bufLink.in);
                    const bufHardwareId = assigner.bufAssigns.getByKey(bufPassId);
                    self.sortedNodes.appendAssumeCapacity(.{ .bufBarrier = .{ .bufId = bufHardwareId, .access = bufSlot.access, .stage = bufSlot.stage } });
                    if (bufSlot.shaderSlot) |slot| self.sortedNodes.appendAssumeCapacity(.{ .setPushDataBufDesc = .{ .bufId = bufHardwareId, .size = @sizeOf(u32), .offset = pushOffset + (slot * @sizeOf(u32)) } });
                },
                .texSlot => |texSlot| {
                    const texPassId = try registry.getTexturePassId(texSlot.texLink.in);
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);
                    self.sortedNodes.appendAssumeCapacity(.{ .texBarrier = .{ .texId = texHardwareId, .access = texSlot.access, .stage = texSlot.stage, .layout = texSlot.layout } });
                    if (texSlot.shaderSlot) |slot| self.sortedNodes.appendAssumeCapacity(.{ .setPushDataTexDesc = .{ .texId = texHardwareId, .size = @sizeOf(u32), .offset = pushOffset + (slot * @sizeOf(u32)), .descTyp = texSlot.descUse } });
                },
                .colorAtt => |attSlot| {
                    const texPassId = try registry.getTexturePassId(attSlot.texLink.in);
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);
                    self.sortedNodes.appendAssumeCapacity(.{ .texBarrier = .{ .texId = texHardwareId, .access = attSlot.access, .stage = attSlot.stage, .layout = attSlot.layout } });
                    if (attSlot.clear != null and attSlot.clear.? != .color) return error.ColorAttNeedsColorClear;
                    self.sortedNodes.appendAssumeCapacity(.{ .setColorAtt = .{ .texId = texHardwareId, .clear = if (attSlot.clear) |clear| clear.color else null } });
                },
                .depthAtt => |depthSlot| {
                    const texPassId = try registry.getTexturePassId(depthSlot.texLink.in);
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);
                    self.sortedNodes.appendAssumeCapacity(.{ .texBarrier = .{ .texId = texHardwareId, .access = depthSlot.access, .stage = depthSlot.stage, .layout = depthSlot.layout } });
                    if (depthSlot.clear != null and depthSlot.clear.? != .depth) return error.DepthAttNeedsDepthClear;
                    self.sortedNodes.appendAssumeCapacity(.{ .setDepthAtt = .{ .texId = texHardwareId, .clear = if (depthSlot.clear) |clear| clear.depth else null } });
                },
                .stencilAtt => |stencilSlot| {
                    const texPassId = try registry.getTexturePassId(stencilSlot.texLink.in);
                    const texHardwareId = assigner.texAssigns.getByKey(texPassId);
                    self.sortedNodes.appendAssumeCapacity(.{ .texBarrier = .{ .texId = texHardwareId, .access = stencilSlot.access, .stage = stencilSlot.stage, .layout = stencilSlot.layout } });
                    if (stencilSlot.clear != null and stencilSlot.clear.? != .depth) return error.StencilAttNeedsDepthClear;
                    self.sortedNodes.appendAssumeCapacity(.{ .setStencilAtt = .{ .texId = texHardwareId, .clear = if (stencilSlot.clear) |clear| clear.depth else null } });
                },
                .vertexBuffer => |vertexBufSlot| {
                    const bufPassId = try registry.getBufferPassId(vertexBufSlot.bufInput);
                    const bufHardwareId = assigner.bufAssigns.getByKey(bufPassId);
                    const vertBufUse = VertexBufferFill{ .bufId = bufHardwareId, .binding = vertexBufSlot.binding, .stride = vertexBufSlot.stride, .inputRate = vertexBufSlot.inputRate };
                    self.sortedNodes.appendAssumeCapacity(.{ .bufBarrier = .{ .bufId = bufHardwareId, .access = .VertexAttributeRead, .stage = .VertexInput } });
                    self.sortedNodes.appendAssumeCapacity(.{ .setVertexBuf = .{ .vertexBuffer = vertBufUse } });
                },
                .indexBuffer => |indexBufSlot| {
                    const bufPassId = try registry.getBufferPassId(indexBufSlot.bufInput);
                    const bufHardwareId = assigner.bufAssigns.getByKey(bufPassId);
                    self.sortedNodes.appendAssumeCapacity(.{ .bufBarrier = .{ .bufId = bufHardwareId, .access = .IndexRead, .stage = .VertexInput } });
                    self.sortedNodes.appendAssumeCapacity(.{ .setIndexBuf = .{ .indexBuffer = .{ .bufId = bufHardwareId, .indexType = indexBufSlot.indexType } } });
                },
                .vertexAttribute => |vertAttrib| {
                    self.sortedNodes.appendAssumeCapacity(.{ .setVertexAttrib = .{ .vertexAttribute = vertAttrib } });
                },
                .renderState => |stateChange| {
                    self.sortedNodes.appendAssumeCapacity(.{ .setRenderStateUnion = stateChange });
                },
                .bufLinking, .texLinking => {},
            }
        }

        self.sortedNodes.appendAssumeCapacity(.bakeBarriers);
        self.sortedNodes.appendAssumeCapacity(.bindShaders);
        self.sortedNodes.appendAssumeCapacity(.bindPushData);

        switch (execution) {
            .dispatch => |dispatch| {
                self.sortedNodes.appendAssumeCapacity(.{ .dispatch = dispatch });
            },
            .dispatchImg => |dispatchImg| {
                self.sortedNodes.appendAssumeCapacity(.{ .dispatchImg = dispatchImg });
            },
            .dispatchIndirect => |dispatchIndirect| {
                self.sortedNodes.appendAssumeCapacity(.{ .dispatchIndirect = dispatchIndirect });
            },
            //
            .drawVertex => |drawVertex| {
                self.sortedNodes.appendAssumeCapacity(.bindRenderState);
                self.sortedNodes.appendAssumeCapacity(.beginRendering);
                self.sortedNodes.appendAssumeCapacity(.setViewportFromOutput);
                self.sortedNodes.appendAssumeCapacity(.setScissorFromOutput);
                self.sortedNodes.appendAssumeCapacity(.bindVertexInput);
                self.sortedNodes.appendAssumeCapacity(.bindIndexInput);
                self.sortedNodes.appendAssumeCapacity(.{ .drawVertex = drawVertex });
                self.sortedNodes.appendAssumeCapacity(.endRendering);
            },
            .drawVertexIndexed => |drawVertexIndexed| {
                self.sortedNodes.appendAssumeCapacity(.bindRenderState);
                self.sortedNodes.appendAssumeCapacity(.beginRendering);
                self.sortedNodes.appendAssumeCapacity(.setViewportFromOutput);
                self.sortedNodes.appendAssumeCapacity(.setScissorFromOutput);
                self.sortedNodes.appendAssumeCapacity(.bindVertexInput);
                self.sortedNodes.appendAssumeCapacity(.bindIndexInput);
                self.sortedNodes.appendAssumeCapacity(.{ .drawVertexIndexed = drawVertexIndexed });
                self.sortedNodes.appendAssumeCapacity(.endRendering);
            },
            //
            .drawTaskOrMesh => |drawTaskOrMesh| {
                self.sortedNodes.appendAssumeCapacity(.bindRenderState);
                self.sortedNodes.appendAssumeCapacity(.beginRendering);
                self.sortedNodes.appendAssumeCapacity(.setViewportFromOutput);
                self.sortedNodes.appendAssumeCapacity(.setScissorFromOutput);
                self.sortedNodes.appendAssumeCapacity(.{ .drawTaskOrMesh = drawTaskOrMesh });
                self.sortedNodes.appendAssumeCapacity(.endRendering);
            },
            .drawTaskOrMeshIndirect => |drawTaskOrMeshIndirect| {
                self.sortedNodes.appendAssumeCapacity(.bindRenderState);
                self.sortedNodes.appendAssumeCapacity(.beginRendering);
                self.sortedNodes.appendAssumeCapacity(.setViewportFromOutput);
                self.sortedNodes.appendAssumeCapacity(.setScissorFromOutput);
                self.sortedNodes.appendAssumeCapacity(.{ .drawTaskOrMeshIndirect = drawTaskOrMeshIndirect });
                self.sortedNodes.appendAssumeCapacity(.endRendering);
            },
            //
            else => return error.IllegalExeuction,
        }

        self.sortedNodes.appendAssumeCapacity(.resetState);

        endTimer(self, timerId);
        endStats(self);
    }
};
