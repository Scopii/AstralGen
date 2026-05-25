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
const pDef = @import("../../.configs/passConfig.zig");
const rc = @import("../../.configs/renderConfig.zig");
const pe = @import("../enums.zig");
const std = @import("std");

const PassExtractorData = @import("PassExtractorData.zig").PassExtractorData;

const TextureEnum = pe.TextureEnum;
const BufferEnum = pe.BufferEnum;
const PassEnum = pe.PassEnum;

pub const PassExtractorSys = struct {
    pub fn build(passExtractor: *PassExtractorData, data: *const EngineData) void {
        const activeViewportIds = data.viewport.activeViewportIds.getConstItems();

        const passEnumFields = @typeInfo(PassEnum).@"enum".fields;
        var passMask: [passEnumFields.len]bool = .{false} ** passEnumFields.len;

        passExtractor.renderNodes.clear();

        // Check every Viewports Pass Order and set passMask
        for (activeViewportIds) |viewportId| {
            const viewport = data.viewport.viewports.getByKey(viewportId.val);
            var lastViewPassEnum: ?PassEnum = null;

            for (0..viewport.passes.len) |i| {
                const viewPassEnum = viewport.passes[i];
                const passIndex = @intFromEnum(viewPassEnum);

                if (lastViewPassEnum) |lastEnum| {
                    if (passIndex <= @intFromEnum(lastEnum)) {
                        std.debug.print("ERROR: Passes in Viewport Slice Out of Order! {} seen after {}\n", .{ viewPassEnum, lastEnum });
                        std.debug.assert(false);
                    }
                }

                passMask[passIndex] = true;
                lastViewPassEnum = viewPassEnum;
                if (rc.PASS_EXTRACTION_DEBUG) std.debug.print("Viewport ({s}) demanded {s}\n", .{ viewport.name, @typeInfo(PassEnum).@"enum".fields[passIndex].name });
            }
        }

        const activeWindows = data.window.activeWindows.constSlice();
        var tempBlitsAndComposits: FixedList(RenderNode, rc.MAX_WINDOWS * 4) = .{};

        for (0..passEnumFields.len) |passIndex| {
            if (passMask[passIndex] == true) {
                const passMaskEnum: PassEnum = @enumFromInt(passIndex);
                var passWidth: u32 = 0;
                var passHeight: u32 = 0;

                // Check Active Windows:
                for (activeWindows) |*window| {
                    // Check all Window Viewports:
                    for (window.viewIds) |windowViewId| {
                        if (windowViewId) |viewId| {
                            const viewport = data.viewport.viewports.getByKey(viewId.val);

                            var usedPass: ?PassEnum = null;

                            for (viewport.passes) |viewPassEnum| {
                                if (viewPassEnum == passMaskEnum) {
                                    usedPass = viewPassEnum;
                                    break; // Found it, stop searching this slice
                                }
                            }

                            // Check if Viewport:
                            if (usedPass) |pass| {

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
                                    if (passMaskEnum == usedBlit) {
                                        const blit = createBlit(&viewport, pass, window.id, window.extent.width, window.extent.height);
                                        tempBlitsAndComposits.append(.{ .viewportBlit = blit }) catch std.debug.print("PassDef Could not Append Blit\n", .{});
                                        break;
                                    }
                                } else {
                                    const composite = createComposite(&viewport, pass, window.id, window.extent.width, window.extent.height);
                                    tempBlitsAndComposits.append(.{ .compositeNode = composite }) catch std.debug.print("PassDef Could not Append Composite\n", .{});
                                }
                            }
                        }
                    }
                }

                // Add Pass
                const pass = createPass(passMaskEnum) orelse continue;
                passExtractor.renderNodes.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } }) catch std.debug.print("ERROR: COULD NOT APPEND PASS\n", .{});
                if (rc.PASS_EXTRACTION_DEBUG) std.debug.print("Pass {s} added (width {} height {})\n", .{ @tagName(passMaskEnum), passWidth, passHeight });

                // Assign Blits/Compsites to SrcTextureId
                if (pass.mainOutputTex) |outputTex| {
                    for (tempBlitsAndComposits.slice()) |*renderNode| {
                        switch (renderNode.*) {
                            .passNode, .uiNode, .clearBuffer, .clearTexture, .barrierBakeClears => unreachable,
                            inline else => |*node| node.srcTexEnum = outputTex, // BLITS AND COMPOSITES GET SRC TEX ENUM!!
                        }
                        passExtractor.renderNodes.append(renderNode.*) catch std.debug.print("PassDef Could not Append Blit\n", .{});
                    }
                }
                tempBlitsAndComposits.clear();
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("1.PassExtractor: \n", .{});
            for (passExtractor.renderNodes.constSlice(), 0..) |*renderNode, i| {
                switch (renderNode.*) {
                    .passNode => |*pass| std.debug.print("- {}. Pass: {s}\n", .{ i, @tagName(pass.pass.name) }),
                    .compositeNode => |*composite| std.debug.print("- {}. Composite: {s} (Pass {})\n", .{ i, composite.name, composite.pass }),
                    .viewportBlit => |*blit| std.debug.print("- {}. Blit: {s} (Pass {})\n", .{ i, blit.name, blit.pass }),
                    .uiNode => |*ui| std.debug.print("- {}. ERROR UI ILLEGAL {s}\n", .{ i, ui.name }),
                    .clearBuffer, .clearTexture, .barrierBakeClears => unreachable,
                }
            }
            std.debug.print("\n", .{});
        }

        for (data.ui.activeNodes) |uiNode| {
            passExtractor.renderNodes.append(.{ .uiNode = uiNode }) catch std.debug.print("Failed to append UiNode\n", .{});
        }
    }

    fn createBlit(viewport: *const Viewport, pass: PassEnum, windowId: WindowId, windowWidth: u32, windowHeight: u32) ViewportBlit {
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

    fn createComposite(viewport: *const Viewport, pass: PassEnum, windowId: WindowId, windowWidth: u32, windowHeight: u32) CompositeNode {
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

    fn createPass(passEnum: PassEnum) ?PassDef {
        switch (passEnum) {
            .CompTest => {
                return pDef.CompRayMarch(.{ // DONE
                    .name = .CompTest,
                    .entityBuf = .{ .in = .EntitySB }, //rc.entitySB.id,
                    .outputTex = .{ .in = .RayMarchInputTex }, //rc.mainTex.id,
                    .camBuf = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                    .readbackBuf = .{ .in = .ReadbackSB }, //rc.readbackSB.id, // SHOULD MAYBE HAVE OUTPUT?
                    .debugTex = .{ .in = .TestTileTex }, //rc.testTilesTex.id,
                });
            },
            .QuantComp => {
                return pDef.QuantComp(.{ // DONE
                    .name = .QuantComp,
                    .indirectBuf = .{ .in = .QuantIndirectInputSB, .out = .QuantIndirectOutputSB }, //rc.indirectSB.id,
                    .entityBuf = .{ .in = .EntitySB }, //rc.entitySB.id,
                });
            },
            .QuantGridMain => { // DONE
                return pDef.QuantGrid(.{
                    .name = .QuantGridMain,
                    .colorAtt = .{ .in = .GridTex }, //rc.mainTex.id,
                    .depthAtt = .{ .in = .GridDepthTex }, //rc.mainDepthTex.id,
                    .indirectBuf = .{ .in = .QuantIndirectOutputSB }, //rc.indirectSB.id,
                    .viewCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                    .cullCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                });
            },
            .QuantGridDebug => {
                return pDef.QuantGrid(.{
                    .name = .QuantGridDebug,
                    .colorAtt = .{ .in = .DebugGridInputTex, .out = .DebugGridOutputTex }, //rc.mainTex.id,
                    .depthAtt = .{ .in = .DebugGridDepthTex }, //rc.debugGridDepthTex.id,
                    .indirectBuf = .{ .in = .QuantIndirectOutputSB }, //rc.indirectSB.id,
                    .viewCam = .{ .in = .DebugCamUB }, // rc.debugCamUB.id,
                    .cullCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                });
            },
            .EditorGridGridDebug => {
                return pDef.EditorGrid(.{
                    .name = .EditorGridGridDebug,
                    .colorAtt = .{ .in = .DebugGridOutputTex }, //rc.mainTex.id,
                    .depthAtt = .{ .in = .DebugGridDepthTex, .out = .DebugGridDepthOutputTex }, //rc.debugGridDepthTex.id,
                    .camBuf = .{ .in = .DebugCamUB }, //rc.debugCamUB.id,
                });
            },
            .EditorGridPlaneDebug => {
                return pDef.EditorGrid(.{
                    .name = .EditorGridPlaneDebug,
                    .colorAtt = .{ .in = .DebugPlaneOutputFrustumViewTex }, //rc.mainTex.id,
                    .depthAtt = .{ .in = .DebugPlaneDepthTex }, //rc.debugPlaneDepthTex.id,
                    .camBuf = .{ .in = .DebugCamUB }, //rc.debugCamUB.id,
                });
            },
            .QuantPlaneMain => { // DONE
                return pDef.QuantPlane(.{
                    .name = .QuantPlaneMain,
                    .colorAtt = .{ .in = .PlaneTex }, //rc.mainTex.id,
                    .depthAtt = .{ .in = .PlaneDepthTex }, //rc.mainDepthTex.id,
                    .indirectBuf = .{ .in = .QuantIndirectOutputSB }, //rc.indirectSB.id,
                    .viewCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                    .cullCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                });
            },
            .QuantPlaneDebug => {
                return pDef.QuantPlane(.{
                    .name = .QuantPlaneDebug,
                    .colorAtt = .{ .in = .DebugPlaneInputTex, .out = .DebugPlaneOutputTex }, //rc.mainTex.id,
                    .depthAtt = .{ .in = .DebugPlaneDepthTex }, //rc.debugPlaneDepthTex.id,
                    .indirectBuf = .{
                        .in = .QuantIndirectOutputSB,
                    }, //rc.indirectSB.id,
                    .viewCam = .{ .in = .DebugCamUB }, //rc.debugCamUB.id,
                    .cullCam = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                });
            },
            .FrustumView => {
                return pDef.FrustumView(.{
                    .name = .FrustumView,
                    .colorAtt = .{ .in = .DebugPlaneOutputTex, .out = .DebugPlaneOutputFrustumViewTex }, //rc.mainTex.id,
                    .depthAtt = .{ .in = .DebugPlaneDepthTex }, //rc.debugPlaneDepthTex.id,
                    .frustumCamBuf = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                    .viewCamBuf = .{ .in = .DebugCamUB }, //rc.debugCamUB.id,
                });
            },
            .DepthView => {
                return pDef.DepthView(.{
                    .name = .DepthView,
                    .outputTex = .{ .in = .DepthViewTex }, //rc.depthViewTex.id,
                    .depthTex = .{ .in = .DebugGridDepthOutputTex }, //rc.debugGridDepthTex.id,
                    .camBuf = .{ .in = .MainCamUB }, //rc.mainCamUB.id,
                });
            },

            .Imgui => return null,

            // .CullComp => {
            //     return pDef.CullComp(.{
            //         .name = "Cull-Comp",
            //         .indirectBuf = .IndirectSB, //rc.indirectSB.id,
            //         .entityBuf = .EntitySB, //rc.entitySB.id,
            //     });
            // },
            // .CullMain => {
            //     return pDef.Cull(.{
            //         .name = "Cull-Main",
            //         .colorAtt = .CullTex, //rc.mainTex.id,
            //         .depthAtt = .CullDepthTex, //rc.mainDepthTex.id,
            //         .indirectBuf = .IndirectSB, //rc.indirectSB.id,
            //         .viewCam = .MainCamUB, //rc.mainCamUB.id,
            //         .cullCam = .MainCamUB, //rc.mainCamUB.id,
            //     });
            // },
            // .CullDebug => {
            //     return pDef.Cull(.{
            //         .name = "Cull-Debug",
            //         .colorAtt = .CullDebugTex, //rc.mainTex.id,
            //         .depthAtt = .CullDebugDepthTex, //rc.debugGridDepthTex.id, swapped!
            //         .indirectBuf = .IndirectSB, //rc.indirectSB.id,
            //         .viewCam = .DebugCamUB, //rc.debugCamUB.id,
            //         .cullCam = .MainCamUB, //rc.mainCamUB.id,
            //     });
            // },
        }
    }
};
