const RenderAssignerData = @import("../renderAssigner/RenderAssignerData.zig").RenderAssignerData;
const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const RenderGraphData = @import("../renderGraph/RenderGraphData.zig").RenderGraphData;
const RenderCompilerData = @import("RenderCompilerData.zig").RenderCompilerData;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

const vk = @import("../.modules/vk.zig").c;

const ImGuiPass = @import("../.assets/passes/Imgui/Imgui.zig").ImGuiPass;

const TaskOrMeshIndirectExec = @import("../render/types/pass/PassInstance.zig").TaskOrMeshIndirectExec;
const ComputeIndirectExec = @import("../render/types/pass/PassInstance.zig").ComputeIndirectExec;
const VertexBufferFill = @import("../render/types/pass/VertexBufferFill.zig").VertexBufferFill;
const IndexBufferFill = @import("../render/types/pass/IndexBufferFill.zig").IndexBufferFill;
const VertexAttribute = @import("../render/types/pass/VertexAttribute.zig").VertexAttribute;
const AttachmentFill = @import("../render/types/pass/AttachmentFill.zig").AttachmentFill;
const PassInstance = @import("../render/types/pass/PassInstance.zig").PassInstance;
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

        for (renderGraph.sorter.sortedRenderIR.constSlice()) |IR| {
            switch (IR) {
                // .uiIR => |uiIR| {},
                .blitIR => |blitIR| {
                    var blitCopy = blitIR;

                    switch (blitIR.srcTexUnion) {
                        .texName => |name| {
                            const texPassId = try registry.getTexturePassId(name);
                            const hardwareTexId = assigner.texAssigns.getByKey(texPassId);
                            blitCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texPassId => |texPassId| {
                            const hardwareTexId = assigner.texAssigns.getByKey(texPassId);
                            blitCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texId => {},
                    }
                    self.sortedNodes.append(.{ .blitNode = blitCopy }) catch std.debug.print("7.PassSorter: Blit Append to sortedRenderNodes failed", .{});
                },
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
                    // self.sortedNodes.append(.{ .compositeNode = compositeCopy }) catch std.debug.print("7.PassSorter: Composite Append to sortedRenderNodes failed", .{});
                    try fillCompositePassHardwareIdCmds(self, assigner, registry, compositeCopy);
                },
                .passIR => |passIR| {
                    try fillPassHardwareIdCmds(self, assigner, registry, renderGraph, passIR, runTime, deltaTime);
                    // const passInstance = try fillPassHardwareIds(self, assigner, registry, passIR, runTime, deltaTime);
                    // self.sortedNodes.append(.{ .passNode = passInstance }) catch std.debug.print("7.PassSorter: Pass Append to sortedRenderNodes failed", .{});
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

        self.usedQueries = 0;

        // Debug Prints
        if (rc.FRAME_GRAPH_DEBUG or true) {
            std.debug.print("Pass Resource Sys:\n", .{});
            for (self.sortedNodes.constSlice(), 0..) |*renderNode, index| {
                switch (renderNode.*) {
                    // .passNode => |*passNode| std.debug.print("- {}. Pass: {s}\n", .{ index, passNode.getName() }),
                    .compositeNode => |*composite| std.debug.print("- {}. Composite: {s} (Pass {s})\n", .{ index, composite.name, try registry.getPassName(composite.pass) }),
                    .blitNode => |*blit| std.debug.print("- {}. Blit: {s} (Pass {s})\n", .{ index, blit.name, try registry.getPassName(blit.pass) }),
                    .uiNode => |*uiNode| std.debug.print("- {}. UI: {s} (WindowID {})\n", .{ index, uiNode.name, uiNode.windowId }),

                    .clearBuffer => |*clearBuf| std.debug.print("- {}. ClearBuffer: BufId {}\n", .{ index, clearBuf.val() }),
                    .clearTexture => |*clearTex| std.debug.print("- {}. ClearTexture: TexId {}\n", .{ index, clearTex.val() }),
                    .barrierBakeClears => std.debug.print("- {}. Bake Clears\n", .{index}),

                    // COMMAND STREAM
                    else => {},
                }
            }
            std.debug.print("\n", .{});
        }
    }

    fn fillCompositePassHardwareIdCmds(self: *RenderCompilerData, _: *const RenderAssignerData, _: *const RenderRegistryData, composite: CompositeNode) !void {
        if (composite.srcTexUnion != .texId) return error.CompositSrcTexIdIsNotHardwareId;

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

        // Push Constants
        const x: f32 = @floatFromInt(composite.viewOffsetX);
        const y: f32 = @floatFromInt(composite.viewOffsetY);
        const viewWidth: f32 = @floatFromInt(composite.viewWidth);
        const viewHeight: f32 = @floatFromInt(composite.viewHeight);
        self.sortedNodes.appendAssumeCapacity(.{ .setScissor = .{ .x = x, .y = y, .width = viewWidth, .height = viewHeight } });
        self.sortedNodes.appendAssumeCapacity(.{ .setViewport = .{ .x = x, .y = y, .width = viewWidth, .height = viewHeight } });

        // const texPassId = try registry.getTexturePassId(drawTex);
        // const texHardwareId = assigner.texAssigns.getByKey(drawTex.texId);
        self.sortedNodes.appendAssumeCapacity(.{ .setPushDataTexDesc = .{ .texId = composite.srcTexUnion.texId, .size = @sizeOf(u32), .offset = 0, .descTyp = .Sampled } });

        var pushData: [128]u8 = undefined;
        @memcpy(pushData[0..][0..4], std.mem.asBytes(&rc.SAMPLER_LINEAR_CLAMP_INDEX));
        const stretch: u32 = if (composite.stretch) 1 else 0;
        @memcpy(pushData[4..][0..4], std.mem.asBytes(&stretch));
        @memcpy(pushData[8..][0..4], std.mem.asBytes(&composite.opacity));
        @memcpy(pushData[12..][0..4], std.mem.asBytes(&composite.viewWidth));
        @memcpy(pushData[16..][0..4], std.mem.asBytes(&composite.viewHeight));
        self.sortedNodes.appendAssumeCapacity(.{ .setPushData = .{ .data = pushData, .size = (5 * @sizeOf(u32)), .offset = @sizeOf(u32) } });
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

            // const pass = ImGuiPass(.{ .string = "Imgui", .vertexBuf = uiNode.imguiVB.bufId, .indexBuf = uiNode.imguiIB.bufId });

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

                // const pushConstants = vhT.ImGuiPushConstants{
                //     .scale = .{ scaleX, scaleY },
                //     .translate = .{ translateX, translateY },
                //     .texDesc = lastTexDesc,
                // };

                var imguiPushData: [128]u8 = undefined;
                @memcpy(imguiPushData[0..][0..4], std.mem.asBytes(&scaleX));
                @memcpy(imguiPushData[4..][0..4], std.mem.asBytes(&scaleY));
                @memcpy(imguiPushData[8..][0..4], std.mem.asBytes(&translateX));
                @memcpy(imguiPushData[12..][0..4], std.mem.asBytes(&translateY));
                self.sortedNodes.appendAssumeCapacity(.{ .setPushData = .{ .data = imguiPushData, .size = (4 * @sizeOf(u32)), .offset = 0 } });

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

        const timerId = try startTimer(self, passName, .Pass);

        self.sortedNodes.appendAssumeCapacity(.{ .setOutputExtent = .{ .mainOutput = mainOutputTexHardwareId } });

        var pushOffset: u32 = 0;

        var data1: [128]u8 = undefined;
        @memcpy(data1[0..][0..4], std.mem.asBytes(&runTime));
        self.sortedNodes.appendAssumeCapacity(.{ .setPushData = .{ .data = data1, .size = @sizeOf(f32), .offset = pushOffset } });
        pushOffset += @sizeOf(u32);

        var data2: [128]u8 = undefined;
        @memcpy(data2[0..][0..4], std.mem.asBytes(&deltaTime));
        self.sortedNodes.appendAssumeCapacity(.{ .setPushData = .{ .data = data2, .size = @sizeOf(f32), .offset = pushOffset } });
        pushOffset += @sizeOf(f32);

        self.sortedNodes.appendAssumeCapacity(.{ .setPushDataOutputExtent = .{ .offset = pushOffset } });
        pushOffset += @sizeOf(f32);
        pushOffset += @sizeOf(f32);

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
                        .graphics => |graphics| {
                            // execution = .{ .graphics = graphics };
                            execution = .{ .drawVertex = .{ .vertexCount = graphics.vertices, .instanceCount = graphics.instances, .firstVertex = 0, .firstInstance = 0 } };

                            // DRAW INDEXED MISSING! PROBABLY NOT CORRECTLY IMPLEMENTED!
                            // execution = .{ .drawVertexIndexed = .{ .indexCount = 0, .instanceCount = graphics.instances, .firstIndex = 0, .vertexOffset = 0, .firstInstance = 0 } };
                        },
                        .computeIndirect => |compIndirect| {
                            const bufPassId = try registry.getBufferPassId(compIndirect.indirectBuf);
                            const bufHardwareId = assigner.bufAssigns.getByKey(bufPassId);
                            execution = .{ .dispatchIndirect = .{ .indirectBuf = bufHardwareId, .indirectBufOffset = compIndirect.indirectBufOffset } };
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
    }
};

// fn buildUiPasses(self: *RenderCompilerData, assigner: *const RenderAssignerData, renderGraph: *const RenderGraphData, registry: *const RenderRegistryData, uiData: *const UiData) void {
//     self.sortedNodes.
// }

const sc = @import("../.configs/shaderConfig.zig");

// fn fillPassHardwareIds(assigner: *const RenderAssignerData, registry: *const RenderRegistryData, passId: PassId) !PassInstance {
//     const passName = try registry.getPassName(passId);
//     const passDef = try registry.getPassDefinition(passName);
//     const mainOutputTexId = if (passDef.outputTex) |output| try registry.getTexturePassId(output) else null;

//     var filledPass = PassInstance{
//         .name = undefined,
//         .execution = undefined,
//         .mainOutputTex = if (mainOutputTexId) |outputId| assigner.texAssigns.getByKey(outputId) else null,
//     };

//     filledPass.name.fill(passDef.name.get());

//     for (passDef.passAttribute.constSlice()) |attribute| {
//         switch (attribute) {
//             .execution => |exec| {
//                 switch (exec) {
//                     .compute => |comp| {
//                         filledPass.execution = .{ .compute = comp };
//                     },
//                     .taskOrMesh => |taskOrMesh| {
//                         filledPass.execution = .{ .taskOrMesh = taskOrMesh };
//                     },
//                     .graphics => |graphics| {
//                         filledPass.execution = .{ .graphics = graphics };
//                     },
//                     .computeIndirect => |compIndirect| {
//                         const bufPassId = try registry.getBufferPassId(compIndirect.indirectBuf);
//                         const compIndirectExec = ComputeIndirectExec{
//                             .indirectBuf = assigner.bufAssigns.getByKey(bufPassId),
//                             .indirectBufOffset = compIndirect.indirectBufOffset,
//                         };
//                         filledPass.execution = .{ .computeIndirect = compIndirectExec };
//                     },
//                     .taskOrMeshIndirect => |taskOrMeshIndirect| {
//                         const bufPassId = try registry.getBufferPassId(taskOrMeshIndirect.indirectBuf);
//                         const taskMeshIndirectExec = TaskOrMeshIndirectExec{
//                             .groupX = taskOrMeshIndirect.groupX,
//                             .groupY = taskOrMeshIndirect.groupY,
//                             .groupZ = taskOrMeshIndirect.groupZ,
//                             .indirectBuf = assigner.bufAssigns.getByKey(bufPassId),
//                             .indirectBufOffset = taskOrMeshIndirect.indirectBufOffset,
//                         };
//                         filledPass.execution = .{ .taskOrMeshIndirect = taskMeshIndirectExec };
//                     },
//                 }
//             },
//             .shaderInf => |shaderInf| {
//                 filledPass.shaderIds.appendAssumeCapacity(shaderInf.id);
//             },
//             .bufSlot => |bufSlot| {
//                 const bufPassId = try registry.getBufferPassId(bufSlot.bufLink.in);
//                 const bufUse = BufferFill{
//                     .bufId = assigner.bufAssigns.getByKey(bufPassId),
//                     .stage = bufSlot.stage,
//                     .access = bufSlot.access,
//                     .shaderSlot = bufSlot.shaderSlot,
//                 };
//                 filledPass.bufUses.appendAssumeCapacity(bufUse);
//             },
//             .texSlot => |texSlot| {
//                 const texPassId = try registry.getTexturePassId(texSlot.texLink.in);
//                 const texUse = TextureFill{
//                     .texId = assigner.texAssigns.getByKey(texPassId),
//                     .stage = texSlot.stage,
//                     .access = texSlot.access,
//                     .layout = texSlot.layout,
//                     .descUse = texSlot.descUse,
//                     .shaderSlot = texSlot.shaderSlot,
//                 };
//                 filledPass.texUses.appendAssumeCapacity(texUse);
//             },
//             .colorAtt => |attSlot| {
//                 const texPassId = try registry.getTexturePassId(attSlot.texLink.in);
//                 const colorAttUse = AttachmentFill{
//                     .texId = assigner.texAssigns.getByKey(texPassId),
//                     .stage = attSlot.stage,
//                     .access = attSlot.access,
//                     .layout = attSlot.layout,
//                     .clear = if (attSlot.clear) |clear| clear else null,
//                 };
//                 filledPass.colorAtts.appendAssumeCapacity(colorAttUse);
//             },
//             .depthAtt => |depthSlot| {
//                 const texPassId = try registry.getTexturePassId(depthSlot.texLink.in);
//                 filledPass.depthAtt = AttachmentFill{
//                     .texId = assigner.texAssigns.getByKey(texPassId),
//                     .stage = depthSlot.stage,
//                     .access = depthSlot.access,
//                     .layout = depthSlot.layout,
//                     .clear = depthSlot.clear,
//                 };
//             },
//             .stencilAtt => |stencilSlot| {
//                 const texPassId = try registry.getTexturePassId(stencilSlot.texLink.in);
//                 filledPass.stencilAtt = AttachmentFill{
//                     .texId = assigner.texAssigns.getByKey(texPassId),
//                     .stage = stencilSlot.stage,
//                     .access = stencilSlot.access,
//                     .layout = stencilSlot.layout,
//                     .clear = stencilSlot.clear,
//                 };
//             },
//             .vertexBuffer => |vertexBufSlot| {
//                 const texPassId = try registry.getBufferPassId(vertexBufSlot.bufInput);
//                 const vertBufUse = VertexBufferFill{
//                     .bufId = assigner.bufAssigns.getByKey(texPassId),
//                     .binding = vertexBufSlot.binding,
//                     .stride = vertexBufSlot.stride,
//                     .inputRate = vertexBufSlot.inputRate,
//                 };
//                 filledPass.vertexBuffers.appendAssumeCapacity(vertBufUse);
//             },
//             .indexBuffer => |indexBufSlot| {
//                 const texPassId = try registry.getBufferPassId(indexBufSlot.bufInput);
//                 filledPass.indexBuffer = IndexBufferFill{ .bufId = assigner.bufAssigns.getByKey(texPassId), .indexType = indexBufSlot.indexType };
//             },
//             .vertexAttribute => |vertAttrib| {
//                 filledPass.vertexAttributes.appendAssumeCapacity(vertAttrib);
//             },
//             .renderState => |stateChange| switch (stateChange) {
//                 inline else => |val, tag| @field(filledPass.renderState, @tagName(tag)) = val,
//             },
//             .bufLinking, .texLinking => {},
//         }
//     }
//     return filledPass;
// }
