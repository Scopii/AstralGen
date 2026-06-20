const CompositeNode = @import("../../render/types/pass/PassDef.zig").CompositeNode;
const TextureMeta = @import("../../render/types/res/TextureMeta.zig").TextureMeta;
const ViewportBlit = @import("../../render/types/pass/PassDef.zig").ViewportBlit;
const BufferMeta = @import("../../render/types/res/BufferMeta.zig").BufferMeta;
const RenderNode = @import("../../render/types/pass/PassDef.zig").RenderNode;
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

const TextureEnum = pe.TextureEnum;
const BufferEnum = pe.BufferEnum;

const CompRayMarch = @import("../../.assets/passes/compTest/CompRayMarch.zig").CompRayMarch;
const EditorGrid = @import("../../.assets/passes/editorGrid/EditorGrid.zig").EditorGrid;
const QuantComp = @import("../../.assets/passes/quant/QuantComp.zig").QuantComp;
const QuantGrid = @import("../../.assets/passes/quant/QuantGrid.zig").QuantGrid;
const QuantPlane = @import("../../.assets/passes/quant/QuantPlane.zig").QuantPlane;
const FrustumView = @import("../../.assets/passes/quant/FrustumView.zig").FrustumView;
const DepthView = @import("../../.assets/passes/depthView/DepthView.zig").DepthView;

pub const PassExtractorSys = struct {
    pub fn newBuild(passExtractor: *PassExtractorData, data: *const EngineData) !void {
        // Cleanup
        passExtractor.renderNodes.clear();
        passExtractor.passStrings.clear();

        // Checking Which Passes are Used
        const activeViewportIds = data.viewport.activeViewportIds.getConstItems();

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
                                    const blit = createBlit(&viewport, .{ .val = @intCast(passStringIndex) }, window.id, window.extent.width, window.extent.height);
                                    tempBlitsAndComposits.append(.{ .viewportBlit = blit }) catch std.debug.print("PassDef Could not Append Blit\n", .{});
                                    break;
                                }
                            } else {
                                const composite = createComposite(&viewport, .{ .val = @intCast(passStringIndex) }, window.id, window.extent.width, window.extent.height);
                                tempBlitsAndComposits.append(.{ .compositeNode = composite }) catch std.debug.print("PassDef Could not Append Composite\n", .{});
                            }
                        }
                    }
                }
            }

            // Add Pass
            const pass = createPass(passString) orelse {
                std.debug.print("ERROR: 1.PassExtractor 1: Could not createPass with passString ({s})!\n", .{passString});
                return error.CreatePass;
            };
            if (passExtractor.renderNodes.isFull() == true) return error.RenderNodesFull;
            passExtractor.renderNodes.upsert(@intCast(passStringIndex), .{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            if (rc.PASS_EXTRACTION_DEBUG) std.debug.print("Pass {s} added (width {} height {})\n", .{ passString, passWidth, passHeight });

            // Assign Blits/Compsites to SrcTextureId
            if (pass.mainOutputTex) |outputTex| {
                for (tempBlitsAndComposits.slice()) |*renderNode| {
                    switch (renderNode.*) {
                        .passNode, .uiNode, .clearBuffer, .clearTexture, .barrierBakeClears => unreachable,
                        inline else => |*node| node.srcTexEnum = outputTex, // BLITS AND COMPOSITES GET SRC TEX ENUM!!
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
                    .passNode => |*pass| std.debug.print("- {}. Pass: {s}\n", .{ i, pass.pass.name }),
                    .compositeNode => |*composite| std.debug.print("- {}. Composite: {s} (Pass {})\n", .{ i, composite.name, composite.pass }),
                    .viewportBlit => |*blit| std.debug.print("- {}. Blit: {s} (Pass {})\n", .{ i, blit.name, blit.pass }),
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

    fn createPass(passString: []const u8) ?PassDef {
        if (std.mem.eql(u8, passString, "CompRayMarch")) {
            return CompRayMarch(.{ // DONE
                .string = "CompRayMarch",
                .entityBuf = .{ .in = .EntitySB }, //rc.entitySB.id,
                .outputTex = .{ .in = .RayMarchInputTex }, //rc.mainTex.id,
                .camBuf = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                .readbackBuf = .{ .in = .ReadbackSB }, //rc.readbackSB.id, // SHOULD MAYBE HAVE OUTPUT?
                .debugTex = .{ .in = .TestTileTex }, //rc.testTilesTex.id,
            });
        }

        if (std.mem.eql(u8, passString, "QuantComp")) {
            return QuantComp(.{ // DONE
                .string = "QuantComp",
                .indirectBuf = .{ .in = .QuantIndirectInputSB, .out = .QuantIndirectOutputSB }, //rc.indirectSB.id,
                .entityBuf = .{ .in = .EntitySB }, //rc.entitySB.id,
            });
        }

        if (std.mem.eql(u8, passString, "QuantGridMain")) {
            return QuantGrid(.{
                .string = "QuantGridMain",
                .colorAtt = .{ .in = .GridTex }, //rc.mainTex.id,
                .depthAtt = .{ .in = .GridDepthTex }, //rc.mainDepthTex.id,
                .indirectBuf = .{ .in = .QuantIndirectOutputSB }, //rc.indirectSB.id,
                .viewCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                .renderCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
            });
        }

        if (std.mem.eql(u8, passString, "QuantGridDebug")) {
            return QuantGrid(.{
                .string = "QuantGridDebug",
                .colorAtt = .{ .in = .DebugGridInputTex, .out = .DebugGridOutputTex }, //rc.mainTex.id,
                .depthAtt = .{ .in = .DebugGridDepthTex }, //rc.debugGridDepthTex.id,
                .indirectBuf = .{ .in = .QuantIndirectOutputSB }, //rc.indirectSB.id,
                .viewCam = .{ .in = .DebugCamUB }, // rc.debugCamUB.id,
                .renderCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
            });
        }

        if (std.mem.eql(u8, passString, "EditorGridGridDebug")) {
            return EditorGrid(.{
                .string = "EditorGridGridDebug",
                .colorAtt = .{ .in = .DebugGridOutputTex }, //rc.mainTex.id,
                .depthAtt = .{ .in = .DebugGridDepthTex, .out = .DebugGridDepthOutputTex }, //rc.debugGridDepthTex.id,
                .camBuf = .{ .in = .DebugCamUB }, //rc.debugCamUB.id,
            });
        }

        if (std.mem.eql(u8, passString, "EditorGridPlaneDebug")) {
            return EditorGrid(.{
                .string = "EditorGridPlaneDebug",
                .colorAtt = .{ .in = .DebugPlaneOutputFrustumViewTex }, //rc.mainTex.id,
                .depthAtt = .{ .in = .DebugPlaneDepthTex }, //rc.debugPlaneDepthTex.id,
                .camBuf = .{ .in = .DebugCamUB }, //rc.debugCamUB.id,
            });
        }

        if (std.mem.eql(u8, passString, "QuantPlaneMain")) {
            return QuantPlane(.{
                .string = "QuantPlaneMain",
                .colorAtt = .{ .in = .PlaneTex }, //rc.mainTex.id,
                .depthAtt = .{ .in = .PlaneDepthTex }, //rc.mainDepthTex.id,
                .indirectBuf = .{ .in = .QuantIndirectOutputSB }, //rc.indirectSB.id,
                .viewCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                .renderCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
            });
        }

        if (std.mem.eql(u8, passString, "QuantPlaneDebug")) {
            return QuantPlane(.{
                .string = "QuantPlaneDebug",
                .colorAtt = .{ .in = .DebugPlaneInputTex, .out = .DebugPlaneOutputTex }, //rc.mainTex.id,
                .depthAtt = .{ .in = .DebugPlaneDepthTex }, //rc.debugPlaneDepthTex.id,
                .indirectBuf = .{
                    .in = .QuantIndirectOutputSB,
                }, //rc.indirectSB.id,
                .viewCam = .{ .in = .DebugCamUB }, //rc.debugCamUB.id,
                .renderCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
            });
        }

        if (std.mem.eql(u8, passString, "FrustumView")) {
            return FrustumView(.{
                .string = "FrustumView",
                .colorAtt = .{ .in = .DebugPlaneOutputTex, .out = .DebugPlaneOutputFrustumViewTex }, //rc.mainTex.id,
                .depthAtt = .{ .in = .DebugPlaneDepthTex }, //rc.debugPlaneDepthTex.id,
                .renderCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                .viewCam = .{ .in = .DebugCamUB }, //rc.debugCamUB.id,
            });
        }

        if (std.mem.eql(u8, passString, "DepthView")) {
            return DepthView(.{
                .string = "DepthView",
                .outputTex = .{ .in = .DepthViewTex }, //rc.depthViewTex.id,
                .depthTex = .{ .in = .DebugGridDepthOutputTex }, //rc.debugGridDepthTex.id,
                .camBuf = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
            });
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
