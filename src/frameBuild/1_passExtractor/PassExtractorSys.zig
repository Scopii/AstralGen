const CompositeNode = @import("../../render/types/pass/RenderNode.zig").CompositeNode;
const TextureMeta = @import("../../render/types/res/TextureMeta.zig").TextureMeta;
const ViewportBlit = @import("../../render/types/pass/RenderNode.zig").ViewportBlit;
const BufferMeta = @import("../../render/types/res/BufferMeta.zig").BufferMeta;
const RenderNode = @import("../../render/types/pass/RenderNode.zig").RenderNode;
const PassDef = @import("../../render/types/pass/PassDef.zig").PassDef;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const WindowId = @import("../../window/Window.zig").Window.WindowId;
const Viewport = @import("../../viewport/Viewport.zig").Viewport;
const EngineData = @import("../../EngineData.zig").EngineData;
const rc = @import("../../.configs/renderConfig.zig");
const PassId = @import("../components.zig").PassId;
const pe = @import("../enums.zig");
const std = @import("std");

const PassExtractorData = @import("PassExtractorData.zig").PassExtractorData;
const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;

// const CompRayMarch = @import("../../.assets/passes/compTest/CompRayMarch.zig").CompRayMarch;
// const EditorGrid = @import("../../.assets/passes/editorGrid/EditorGrid.zig").EditorGrid;
// const QuantComp = @import("../../.assets/passes/quant/QuantComp.zig").QuantComp;
// const QuantGrid = @import("../../.assets/passes/quant/QuantGrid.zig").QuantGrid;
// const QuantPlane = @import("../../.assets/passes/quant/QuantPlane.zig").QuantPlane;
// const FrustumView = @import("../../.assets/passes/quant/FrustumView.zig").FrustumView;
// const DepthView = @import("../../.assets/passes/depthView/DepthView.zig").DepthView;

const RenderStateUnion = @import("../../render/types/pass/RenderState.zig").RenderStateUnion;
const VertexBufferSlot = @import("../../render/types/pass/VertexBufferSlot.zig").VertexBufferSlot;
const IndexBufferSlot = @import("../../render/types/pass/IndexBufferSlot.zig").IndexBufferSlot;
const AttachmentSlot = @import("../../render/types/pass/AttachmentSlot.zig").AttachmentSlot;
const PassExecution = @import("../../render/types/pass/PassDef.zig").PassDef.PassExecution;
const ShaderId = @import("../../shader/ShaderSys.zig").ShaderId;
const RenderState = @import("../../render/types/pass/RenderState.zig").RenderState;
const TexId = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexId;
const TextureSlot = @import("../../render/types/pass/TextureSlot.zig").TextureSlot;
const BufferSlot = @import("../../render/types/pass/BufferSlot.zig").BufferSlot;
const BufferUse = @import("../../render/types/pass/BufferUse.zig").BufferUse;
const TextureUse = @import("../../render/types/pass/TextureUse.zig").TextureUse;
const AttachmentUse = @import("../../render/types/pass/AttachmentUse.zig").AttachmentUse;
const VertexBufferUse = @import("../../render/types/pass/VertexBufferUse.zig").VertexBufferUse;
const IndexBufferUse = @import("../../render/types/pass/IndexBufferUse.zig").IndexBufferUse;
const VertexAttribute = @import("../../render/types/pass/VertexAttribute.zig").VertexAttribute;

const ComputeIndirectExec = @import("../../render/types/pass/PassDef.zig").ComputeIndirectExec;
const TaskOrMeshIndirectExec = @import("../../render/types/pass/PassDef.zig").TaskOrMeshIndirectExec;

pub const PassExtractorSys = struct {
    pub fn newBuild(passExtractor: *PassExtractorData, resourceRegistry: *const ResourceRegistryData, data: *const EngineData) !void {
        // Cleanup
        passExtractor.renderNodes.clear();
        passExtractor.passStrings.clear();

        // Checking Which Passes are Used
        const activeViewportIds = data.viewport.activeViewportIds.getConstItems();

        // SHOULD BE IMPROVED USING A HASH MAP INSTEAD OF ITERATING ALL PASSES FOR EVERY NEW PASS!
        for (activeViewportIds) |viewportId| {
            const viewport = data.viewport.viewports.getByKey(viewportId.val);

            for (viewport.stringPasses) |stringPass| {
                var passExists = false;
                // Validate Pass does not exist yet
                for (passExtractor.passStrings.getConstItems()) |passString| {
                    if (std.mem.eql(u8, passString, stringPass)) {
                        passExists = true;
                        break;
                    }
                }
                // If pass does not exist: insert else break
                if (passExists == false) {
                    const key = passExtractor.passStrings.getLength();
                    passExtractor.passStrings.insert(@intCast(key), stringPass);
                }
            }
        }

        // Preping
        const activeWindows = data.window.activeWindows.constSlice();
        var tempBlitsAndComposits: FixedList(RenderNode, rc.MAX_WINDOWS * 4) = .{};

        for (0..passExtractor.passStrings.getLength()) |passStringIndex| {
            const passString = passExtractor.passStrings.getByIndex(@intCast(passStringIndex));
            const passId = try resourceRegistry.getPassId(passString);
            var passWidth: u32 = 0;
            var passHeight: u32 = 0;

            // Active Windows
            for (activeWindows) |*window| {
                // Window Viewports
                for (window.viewIds) |windowViewId| {
                    if (windowViewId) |viewId| {
                        const viewport = data.viewport.viewports.getByKey(viewId.val);

                        var usedPass: ?[]const u8 = null;

                        for (viewport.stringPasses) |stringPass| {
                            if (std.mem.eql(u8, stringPass, passString)) {
                                usedPass = stringPass;
                                break; // Found it, stop searching this slice
                            }
                        }

                        if (usedPass) |_| {
                            // Check for bigger Viewport Area:
                            const viewWidth = viewport.calcViewWidth(window.extent.width);
                            if (viewWidth > passWidth) {
                                passWidth = viewWidth;
                                // if (rc.FRAME_BUILD_DEBUG) std.debug.print("{s} set PassDef Width to {}\n", .{ viewport.name, viewWidth });
                            }
                            const viewHeight = viewport.calcViewHeight(window.extent.height);
                            if (viewHeight > passHeight) {
                                passHeight = viewHeight;
                                // if (rc.FRAME_BUILD_DEBUG) std.debug.print("{s} set PassDef Height to {}\n", .{ viewport.name, viewHeight });
                            }

                            // Check Blit or Composite
                            if (viewport.blitPass) |usedBlit| {
                                if (std.mem.eql(u8, passString, usedBlit)) {
                                    const blit = createBlit(&viewport, passId, window.id, window.extent.width, window.extent.height);
                                    tempBlitsAndComposits.append(.{ .viewportBlit = blit }) catch std.debug.print("PassDef Could not Append Blit\n", .{});
                                    break;
                                }
                            } else {
                                const composite = createComposite(&viewport, passId, window.id, window.extent.width, window.extent.height);
                                tempBlitsAndComposits.append(.{ .compositeNode = composite }) catch std.debug.print("PassDef Could not Append Composite\n", .{});
                            }
                        }
                    }
                }
            }

            // Add Pass
            const pass = createPass(passString, resourceRegistry) orelse {
                std.debug.print("ERROR: 1.PassExtractor 1: Could not createPass with passString ({s})!\n", .{passString});
                return error.CreatePass;
            };
            if (passExtractor.renderNodes.isFull() == true) return error.RenderNodesFull;
            passExtractor.renderNodes.upsert(passId.val(), .{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            if (rc.PASS_EXTRACTION_DEBUG) std.debug.print("Pass {s} added (width {} height {})\n", .{ passString, passWidth, passHeight });

            // Assign Blits/Compsites to SrcTextureId
            if (pass.mainOutputTex) |outputTex| {
                for (tempBlitsAndComposits.slice()) |*renderNode| {
                    switch (renderNode.*) {
                        .passNode, .uiNode, .clearBuffer, .clearTexture, .barrierBakeClears => unreachable,
                        inline else => |*node| node.srcTexPassId = outputTex, // BLITS AND COMPOSITES GET SRC TEX ENUM!!
                    }
                    if (passExtractor.renderNodes.isFull() == true) return error.RenderNodesFull;
                    passExtractor.renderNodes.appendUnlinked(renderNode.*);
                }
            }
            tempBlitsAndComposits.clear();
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("1.PassExtractor: \n", .{});
            for (passExtractor.renderNodes.getConstItems(), 0..) |*renderNode, i| {
                switch (renderNode.*) {
                    .passNode => |*pass| std.debug.print("- {}. Pass: {s}\n", .{ i, pass.pass.getName() }),
                    .compositeNode => |*composite| std.debug.print("- {}. Composite: {s} (Pass {s})\n", .{ i, composite.name, try resourceRegistry.getPassName(composite.pass) }),
                    .viewportBlit => |*blit| std.debug.print("- {}. Blit: {s} (Pass {s})\n", .{ i, blit.name, try resourceRegistry.getPassName(blit.pass) }),
                    .uiNode => |*ui| std.debug.print("- {}. ERROR UI ILLEGAL {s}\n", .{ i, ui.name }),
                    .clearBuffer, .clearTexture, .barrierBakeClears => unreachable,
                }
            }
            std.debug.print("\n", .{});
        }
    }

    fn createBlit(viewport: *const Viewport, pass: PassId, windowId: WindowId, windowWidth: u32, windowHeight: u32) ViewportBlit {
        return ViewportBlit{
            .name = viewport.name,
            .pass = pass,
            // .srcTexId = null, USED FROM PASS
            .dstWindowId = windowId,
            .viewWidth = viewport.calcViewWidth(windowWidth),
            .viewHeight = viewport.calcViewHeight(windowHeight),
            .viewOffsetX = viewport.calcViewX(windowWidth),
            .viewOffsetY = viewport.calcViewY(windowHeight),
        };
    }

    fn createComposite(viewport: *const Viewport, pass: PassId, windowId: WindowId, windowWidth: u32, windowHeight: u32) CompositeNode {
        return CompositeNode{
            .name = viewport.name,
            .pass = pass,
            // .srcTexId = null, USED FROM PASS
            .windowId = windowId,
            .viewWidth = viewport.calcViewWidth(windowWidth),
            .viewHeight = viewport.calcViewHeight(windowHeight),
            .viewOffsetX = viewport.calcViewX(windowWidth),
            .viewOffsetY = viewport.calcViewY(windowHeight),
            .opacity = viewport.opacity,
            .stretch = rc.RENDER_TEX_STRETCH,
        };
    }

    pub fn fillPassDefinition(resourceRegistry: *const ResourceRegistryData, passName: []const u8) !PassDef {
        const passDef = try resourceRegistry.getPassDefinition(passName);

        var filledPass = PassDef{
            .name = undefined,
            .execution = undefined,
            .mainOutputTex = if (passDef.outputTex) |output| try resourceRegistry.getTexturePassId(output) else null,
        };

        filledPass.name.fill(passDef.name.get());

        for (passDef.passAttribute.constSlice()) |attribute| {
            switch (attribute) {
                .execution => |exec| {
                    switch (exec) {
                        .computeIndirect => |compIndirect| {
                            const compIndirectExec = ComputeIndirectExec{
                                .indirectBuf = try resourceRegistry.getBufferPassId(compIndirect.indirectBuf),
                                .indirectBufOffset = compIndirect.indirectBufOffset,
                            };
                            filledPass.execution = .{ .computeIndirect = compIndirectExec };
                        },
                        .taskOrMeshIndirect => |taskOrMeshIndirect| {
                            const taskMeshIndirectExec = TaskOrMeshIndirectExec{
                                .workgroups = taskOrMeshIndirect.workgroups,
                                .indirectBuf = try resourceRegistry.getBufferPassId(taskOrMeshIndirect.indirectBuf),
                                .indirectBufOffset = taskOrMeshIndirect.indirectBufOffset,
                            };
                            filledPass.execution = .{ .taskOrMeshIndirect = taskMeshIndirectExec };
                        },
                        .compute => |comp| {
                            filledPass.execution = .{ .compute = comp };
                        },
                        .taskOrMesh => |taskOrMesh| {
                            filledPass.execution = .{ .taskOrMesh = taskOrMesh };
                        },
                        .graphics => |graphics| {
                            filledPass.execution = .{ .graphics = graphics };
                        },
                        // inline else => |val, tag| @field(filledPass.execution, @tagName(tag)) = val,
                    }
                },
                .shaderInf => |shaderInf| {
                    filledPass.shaderIds.appendAssumeCapacity(shaderInf.id);
                },
                .bufSlot => |bufSlot| {
                    const bufUse = BufferUse{
                        .bufLink = .{
                            .in = try resourceRegistry.getBufferPassId(bufSlot.bufLink.in),
                            .out = if (bufSlot.bufLink.out) |output| try resourceRegistry.getBufferPassId(output) else null,
                        },
                        .stage = bufSlot.stage,
                        .access = bufSlot.access,
                        .shaderSlot = bufSlot.shaderSlot,
                    };
                    filledPass.bufUses.appendAssumeCapacity(bufUse);
                },
                .texSlot => |texSlot| {
                    const texUse = TextureUse{
                        .texLink = .{
                            .in = try resourceRegistry.getTexturePassId(texSlot.texLink.in),
                            .out = if (texSlot.texLink.out) |output| try resourceRegistry.getTexturePassId(output) else null,
                        },
                        .stage = texSlot.stage,
                        .access = texSlot.access,
                        .layout = texSlot.layout,
                        .descUse = texSlot.descUse,
                        .shaderSlot = texSlot.shaderSlot,
                    };
                    filledPass.texUses.appendAssumeCapacity(texUse);
                },

                .colorAtt => |attSlot| {
                    const colorAttUse = AttachmentUse{
                        .texLink = .{
                            .in = try resourceRegistry.getTexturePassId(attSlot.texLink.in),
                            .out = if (attSlot.texLink.out) |output| try resourceRegistry.getTexturePassId(output) else null,
                        },
                        .stage = attSlot.stage,
                        .access = attSlot.access,
                        .layout = attSlot.layout,
                        .clear = if (attSlot.clear) |clear| clear else null,
                    };
                    filledPass.colorAtts.appendAssumeCapacity(colorAttUse);
                },
                .depthAtt => |depthSlot| {
                    const depthAttUse = AttachmentUse{
                        .texLink = .{
                            .in = try resourceRegistry.getTexturePassId(depthSlot.texLink.in),
                            .out = if (depthSlot.texLink.out) |output| try resourceRegistry.getTexturePassId(output) else null,
                        },
                        .stage = depthSlot.stage,
                        .access = depthSlot.access,
                        .layout = depthSlot.layout,
                        .clear = depthSlot.clear,
                    };
                    filledPass.depthAtt = depthAttUse;
                },
                .stencilAtt => |stencilSlot| {
                    filledPass.stencilAtt = AttachmentUse{
                        .texLink = .{
                            .in = try resourceRegistry.getTexturePassId(stencilSlot.texLink.in),
                            .out = if (stencilSlot.texLink.out) |output| try resourceRegistry.getTexturePassId(output) else null,
                        },
                        .stage = stencilSlot.stage,
                        .access = stencilSlot.access,
                        .layout = stencilSlot.layout,
                        .clear = stencilSlot.clear,
                    };
                },

                .vertexBuffer => |vertexBufSlot| {
                    const vertBufUse = VertexBufferUse{
                        .bufInput = try resourceRegistry.getBufferPassId(vertexBufSlot.bufInput),
                        .binding = vertexBufSlot.binding,
                        .stride = vertexBufSlot.stride,
                        .inputRate = vertexBufSlot.inputRate,
                    };
                    filledPass.vertexBuffers.appendAssumeCapacity(vertBufUse);
                },
                .indexBuffer => |indexBufSlot| {
                    filledPass.indexBuffer = IndexBufferUse{
                        .bufInput = try resourceRegistry.getBufferPassId(indexBufSlot.bufInput),
                        .indexType = indexBufSlot.indexType,
                    };
                },
                .vertexAttribute => |vertAttrib| {
                    filledPass.vertexAttributes.appendAssumeCapacity(vertAttrib);
                },
                .renderState => |stateChange| switch (stateChange) {
                    inline else => |val, tag| @field(filledPass.renderState, @tagName(tag)) = val,
                },
            }
        }

        return filledPass;
    }

    fn createPass(passString: []const u8, resourceRegistry: *const ResourceRegistryData) ?PassDef {
        if (std.mem.eql(u8, passString, "CompRayMarch")) {
            // return CompRayMarch(.{
            //     .string = "CompRayMarch",
            //     .entityBuf = .{ .in = rc.EntitySB }, // "EntitySB"
            //     .outputTex = .{ .in = rc.RayMarchInputTex }, // "RayMarchInputTex"
            //     .camBuf = .{ .in = rc.MainCamUB }, // "MainCamUB"
            //     .readbackBuf = .{ .in = rc.ReadbackSB }, // "ReadbackSB"
            //     .debugTex = .{ .in = rc.TestTileTex }, // "TestTileTex"
            // });
            return fillPassDefinition(resourceRegistry, "CompRayMarch") catch |err| {
                std.debug.print("ERROR: CompRayMarch fillPassDefinition failed: {}\n", .{err});
                return null;
            };
        }

        if (std.mem.eql(u8, passString, "QuantComp")) {
            // return QuantComp(.{
            //     .string = "QuantComp",
            //     .indirectBuf = .{ .in = rc.QuantIndirectInputSB, .out = rc.QuantIndirectOutputSB }, // "QuantIndirectInputSB" "QuantIndirectOutputSB"
            //     .entityBuf = .{ .in = rc.EntitySB }, // "EntitySB"
            // });
            return fillPassDefinition(resourceRegistry, "QuantComp") catch |err| {
                std.debug.print("ERROR: QuantComp fillPassDefinition failed: {}\n", .{err});
                return null;
            };
        }

        if (std.mem.eql(u8, passString, "QuantGridMain")) {
            // return QuantGrid(.{
            //     .string = "QuantGridMain",
            //     .colorAtt = .{ .in = rc.GridTex }, // "GridTex"
            //     .depthAtt = .{ .in = rc.GridDepthTex }, // "GridDepthTex"
            //     .indirectBuf = .{ .in = rc.QuantIndirectOutputSB }, // "QuantIndirectOutputSB"
            //     .viewCam = .{ .in = rc.MainCamUB }, // "MainCamUB"
            //     .renderCam = .{ .in = rc.MainCamUB }, // "MainCamUB"
            // });
            return fillPassDefinition(resourceRegistry, "QuantGridMain") catch |err| {
                std.debug.print("ERROR: QuantGridMain fillPassDefinition failed: {}\n", .{err});
                return null;
            };
        }

        if (std.mem.eql(u8, passString, "QuantGridDebug")) {
            // return QuantGrid(.{
            //     .string = "QuantGridDebug",
            //     .colorAtt = .{ .in = rc.DebugGridInputTex, .out = rc.DebugGridOutputTex }, // "DebugGridInputTex" "DebugGridOutputTex"
            //     .depthAtt = .{ .in = rc.DebugGridDepthTex }, // "DebugGridDepthTex"
            //     .indirectBuf = .{ .in = rc.QuantIndirectOutputSB }, // "QuantIndirectOutputSB"
            //     .viewCam = .{ .in = rc.DebugCamUB }, // "DebugCamUB"
            //     .renderCam = .{ .in = rc.MainCamUB }, // "MainCamUB"
            // });
            return fillPassDefinition(resourceRegistry, "QuantGridDebug") catch |err| {
                std.debug.print("ERROR: QuantGridDebug fillPassDefinition failed: {}\n", .{err});
                return null;
            };
        }

        if (std.mem.eql(u8, passString, "EditorGridGridDebug")) {
            // return EditorGrid(.{
            //     .string = "EditorGridGridDebug",
            //     .colorAtt = .{ .in = rc.DebugGridOutputTex }, // "DebugGridOutputTex"
            //     .depthAtt = .{ .in = rc.DebugGridDepthTex, .out = rc.DebugGridDepthOutputTex }, // "DebugGridDepthTex" "DebugGridDepthOutputTex"
            //     .camBuf = .{ .in = rc.DebugCamUB }, // "DebugCamUB"
            // });
            return fillPassDefinition(resourceRegistry, "EditorGridGridDebug") catch |err| {
                std.debug.print("ERROR: EditorGridGridDebug fillPassDefinition failed: {}\n", .{err});
                return null;
            };
        }

        if (std.mem.eql(u8, passString, "EditorGridPlaneDebug")) {
            // return EditorGrid(.{
            //     .string = "EditorGridPlaneDebug",
            //     .colorAtt = .{ .in = rc.DebugPlaneOutputFrustumViewTex }, // "DebugPlaneOutputFrustumViewTex"
            //     .depthAtt = .{ .in = rc.DebugPlaneDepthTex }, // "DebugPlaneDepthTex"
            //     .camBuf = .{ .in = rc.DebugCamUB }, // "DebugCamUB"
            // });
            return fillPassDefinition(resourceRegistry, "EditorGridPlaneDebug") catch |err| {
                std.debug.print("ERROR: EditorGridPlaneDebug fillPassDefinition failed: {}\n", .{err});
                return null;
            };
        }

        if (std.mem.eql(u8, passString, "QuantPlaneMain")) {
            // return QuantPlane(.{
            //     .string = "QuantPlaneMain",
            //     .colorAtt = .{ .in = rc.PlaneTex },
            //     .depthAtt = .{ .in = rc.PlaneDepthTex },
            //     .indirectBuf = .{ .in = rc.QuantIndirectOutputSB }, // "QuantIndirectOutputSB"
            //     .viewCam = .{ .in = rc.MainCamUB }, // "MainCamUB"
            //     .renderCam = .{ .in = rc.MainCamUB }, // "MainCamUB"
            // });
            return fillPassDefinition(resourceRegistry, "QuantPlaneMain") catch |err| {
                std.debug.print("ERROR: QuantPlaneMain fillPassDefinition failed: {}\n", .{err});
                return null;
            };
        }

        if (std.mem.eql(u8, passString, "QuantPlaneDebug")) {
            // return QuantPlane(.{
            //     .string = "QuantPlaneDebug",
            //     .colorAtt = .{ .in = rc.DebugPlaneInputTex, .out = rc.DebugPlaneOutputTex }, // "DebugPlaneInputTex" "DebugPlaneOutputTex"
            //     .depthAtt = .{ .in = rc.DebugPlaneDepthTex }, // "DebugPlaneDepthTex"
            //     .indirectBuf = .{ .in = rc.QuantIndirectOutputSB }, // "QuantIndirectOutputSB"
            //     .viewCam = .{ .in = rc.DebugCamUB }, // "DebugCamUB"
            //     .renderCam = .{ .in = rc.MainCamUB }, // "MainCamUB"
            // });
            return fillPassDefinition(resourceRegistry, "QuantPlaneDebug") catch |err| {
                std.debug.print("ERROR: QuantPlaneDebug fillPassDefinition failed: {}\n", .{err});
                return null;
            };
        }

        if (std.mem.eql(u8, passString, "FrustumView")) {
            // return FrustumView(.{
            //     .string = "FrustumView",
            //     .colorAtt = .{ .in = rc.DebugPlaneOutputTex, .out = rc.DebugPlaneOutputFrustumViewTex }, // "DebugPlaneOutputTex" "DebugPlaneOutputFrustumViewTex"
            //     .depthAtt = .{ .in = rc.DebugPlaneDepthTex }, // "DebugPlaneDepthTex"
            //     .renderCam = .{ .in = rc.MainCamUB }, // "MainCamUB"
            //     .viewCam = .{ .in = rc.DebugCamUB }, // "DebugCamUB"
            // });
            return fillPassDefinition(resourceRegistry, "FrustumView") catch |err| {
                std.debug.print("ERROR: FrustumView fillPassDefinition failed: {}\n", .{err});
                return null;
            };
        }

        if (std.mem.eql(u8, passString, "DepthView")) {
            // return DepthView(.{
            //     .string = "DepthView",
            //     .outputTex = .{ .in = rc.DepthViewTex },
            //     .depthTex = .{ .in = rc.DebugGridDepthOutputTex },
            //     .camBuf = .{ .in = rc.MainCamUB },
            // });

            // return fillPassDefinition(resourceRegistry, "DepthView") catch {
            //     // std.debug.print("ERROR: 1.PassExtractor: Could not find Pass Definition ({s})\n", .{passString});
            //     return null;
            // };

            return fillPassDefinition(resourceRegistry, "DepthView") catch |err| {
                std.debug.print("ERROR: DepthView fillPassDefinition failed: {}\n", .{err});
                return null;
            };
        }

        return null;

        // switch (passEnum) {
        //     .Imgui,
        //     .Composite,
        //     => return null,

        //     // .CullComp => {
        //     //     return pDef.CullComp(.{
        //     //         .name = "Cull-Comp",
        //     //         .indirectBuf = .IndirectSB, //rc.indirectSB.id,
        //     //         .entityBuf = .EntitySB, //rc.entitySB.id,
        //     //     });
        //     // },
        //     // .CullMain => {
        //     //     return pDef.Cull(.{
        //     //         .name = "Cull-Main",
        //     //         .colorAtt = .CullTex, //rc.mainTex.id,
        //     //         .depthAtt = .CullDepthTex, //rc.mainDepthTex.id,
        //     //         .indirectBuf = .IndirectSB, //rc.indirectSB.id,
        //     //         .viewCam = .MainCamUB, //rc.mainCamUB.id,
        //     //         .cullCam = .MainCamUB, //rc.mainCamUB.id,
        //     //     });
        //     // },
        //     // .CullDebug => {
        //     //     return pDef.Cull(.{
        //     //         .name = "Cull-Debug",
        //     //         .colorAtt = .CullDebugTex, //rc.mainTex.id,
        //     //         .depthAtt = .CullDebugDepthTex, //rc.debugGridDepthTex.id, swapped!
        //     //         .indirectBuf = .IndirectSB, //rc.indirectSB.id,
        //     //         .viewCam = .DebugCamUB, //rc.debugCamUB.id,
        //     //         .cullCam = .MainCamUB, //rc.mainCamUB.id,
        //     //     });
        //     // },
        // }
    }
};
