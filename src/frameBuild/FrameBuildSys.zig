const CompositeNode = @import("../render/types/pass/PassDef.zig").CompositeNode;
const TexId = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexId;
const ViewportBlit = @import("../render/types/pass/PassDef.zig").ViewportBlit;
const RenderNode = @import("../render/types/pass/PassDef.zig").RenderNode;
const PassDef = @import("../render/types/pass/PassDef.zig").PassDef;
const FrameBuildData = @import("FrameBuildData.zig").FrameBuildData;
const WindowId = @import("../window/Window.zig").Window.WindowId;
const Viewport = @import("../viewport/Viewport.zig").Viewport;
const EngineData = @import("../EngineData.zig").EngineData;
const pDef = @import("../.configs/passConfig.zig");
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

const FixedList = @import("../.structures/FixedList.zig").FixedList;

pub const PassEnum = enum {
    CullComp,
    CullMain,
    CullDebug,

    QuantComp,
    QuantGridMain,
    QuantGridDebug,
    QuantPlaneMain,
    QuantPlaneDebug,

    FrustumView,

    DepthView,

    CompTest,

    EditorGridGridDebug,
    EditorGridPlaneDebug,
};

pub const FrameBuildSys = struct {
    pub fn build(frameBuild: *FrameBuildData, data: *const EngineData) void {
        const activeViewportIds = data.viewport.activeViewportIds.getConstItems();

        const passEnumFields = @typeInfo(PassEnum).@"enum".fields;
        var passMask: [passEnumFields.len]bool = .{false} ** passEnumFields.len;

        frameBuild.passList.clear();

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
                if (rc.FRAME_BUILD_DEBUG) std.debug.print("Viewport ({s}) demanded {s}\n", .{ viewport.name, @typeInfo(PassEnum).@"enum".fields[passIndex].name });
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

                            var usesPass = false;
                            for (viewport.passes) |viewPassEnum| {
                                if (viewPassEnum == passMaskEnum) {
                                    usesPass = true;
                                    break; // Found it, stop searching this slice
                                }
                            }

                            // Check if Viewport:
                            if (usesPass) {

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
                                        const blit = createBlit(&viewport, window.id, window.extent.width, window.extent.height);
                                        tempBlitsAndComposits.append(.{ .viewportBlit = blit }) catch std.debug.print("PassDef Could not Append Blit\n", .{});
                                        break;
                                    }
                                } else {
                                    const composite = createComposite(&viewport, window.id, window.extent.width, window.extent.height);
                                    tempBlitsAndComposits.append(.{ .compositeNode = composite }) catch std.debug.print("PassDef Could not Append Composite\n", .{});
                                }
                            }
                        }
                    }
                }

                // Add Pass
                const pass = createPass(passMaskEnum);
                frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } }) catch std.debug.print("ERROR: COULD NOT APPEND PASS\n", .{});
                if (rc.FRAME_BUILD_DEBUG) std.debug.print("Pass {s} added (width {} height {})\n", .{ @enumFromInt(passIndex), passWidth, passHeight });

                // Assign Blits/Compsites to SrcTextureId
                if (pass.outputTexId) |outputTexId| {
                    for (tempBlitsAndComposits.slice()) |*renderNode| {
                        switch (renderNode.*) {
                            .passNode, .uiNode => unreachable,
                            inline else => |*node| node.srcTexId = outputTexId,
                        }
                        frameBuild.passList.append(renderNode.*) catch std.debug.print("PassDef Could not Append Blit\n", .{});
                    }
                }
                tempBlitsAndComposits.clear();
            }
        }

        for (data.ui.activeNodes) |uiNode| {
            frameBuild.passList.append(.{ .uiNode = uiNode }) catch std.debug.print("Failed to append UiNode\n", .{});
        }
    }

    fn createBlit(viewport: *const Viewport, windowId: WindowId, windowWidth: u32, windowHeight: u32) ViewportBlit {
        return ViewportBlit{
            .name = viewport.name,
            // .srcTexId = null, USED FROM PASS
            .dstWindowId = windowId,
            .viewWidth = viewport.calcViewWidth(windowWidth),
            .viewHeight = viewport.calcViewHeight(windowHeight),
            .viewOffsetX = viewport.calcViewX(windowWidth),
            .viewOffsetY = viewport.calcViewY(windowHeight),
        };
    }

    fn createComposite(viewport: *const Viewport, windowId: WindowId, windowWidth: u32, windowHeight: u32) CompositeNode {
        return CompositeNode{
            .name = viewport.name,
            .windowId = windowId,
            // .srcTexId = null, USED FROM PASS
            .viewWidth = viewport.calcViewWidth(windowWidth),
            .viewHeight = viewport.calcViewHeight(windowHeight),
            .viewOffsetX = viewport.calcViewX(windowWidth),
            .viewOffsetY = viewport.calcViewY(windowHeight),
            .opacity = viewport.opacity,
            .stretch = rc.RENDER_TEX_STRETCH,
        };
    }

    fn createPass(passEnum: PassEnum) PassDef {
        switch (passEnum) {
            .CompTest => {
                return pDef.CompRayMarch(.{
                    .name = "Compute-Ray-March",
                    .entityBuf = rc.entitySB.id,
                    .outputTex = rc.mainTex.id,
                    .camBuf = rc.mainCamUB.id,
                    .readbackBuf = rc.readbackSB.id,
                    .debugTex = rc.testTilesTex.id,
                });
            },
            .CullComp => {
                return pDef.CullComp(.{
                    .name = "Cull-Comp",
                    .indirectBuf = rc.indirectSB.id,
                    .entityBuf = rc.entitySB.id,
                });
            },
            .CullMain => {
                return pDef.Cull(.{
                    .name = "Cull-Main",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.mainCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
            },
            .CullDebug => {
                return pDef.Cull(.{
                    .name = "Cull-Debug",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.debugGridDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.debugCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
            },
            .QuantComp => {
                return pDef.QuantComp(.{
                    .name = "Quant-Comp",
                    .indirectBuf = rc.indirectSB.id,
                    .entityBuf = rc.entitySB.id,
                });
            },
            .QuantGridMain => {
                return pDef.QuantGrid(.{
                    .name = "QuantGrid-Main",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.mainCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
            },
            .QuantGridDebug => {
                return pDef.QuantGrid(.{
                    .name = "QuantGrid-Debug",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.debugGridDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.debugCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
            },
            .EditorGridGridDebug => {
                return pDef.EditorGrid(.{
                    .name = "Editor-Grid",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.debugGridDepthTex.id,
                    .camBuf = rc.debugCamUB.id,
                });
            },
            .EditorGridPlaneDebug => {
                return pDef.EditorGrid(.{
                    .name = "Editor-Grid",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.debugPlaneDepthTex.id,
                    .camBuf = rc.debugCamUB.id,
                });
            },
            .QuantPlaneMain => {
                return pDef.QuantPlane(.{
                    .name = "QuantPlane-Main",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.mainCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
            },
            .QuantPlaneDebug => {
                return pDef.QuantPlane(.{
                    .name = "QuantPlane-Debug",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.debugPlaneDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.debugCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
            },
            .FrustumView => {
                return pDef.FrustumView(.{
                    .name = "FrustumView",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.debugPlaneDepthTex.id,
                    .frustumCamBuf = rc.mainCamUB.id,
                    .viewCamBuf = rc.debugCamUB.id,
                });
            },
            .DepthView => {
                return pDef.DepthView(.{
                    .name = "Depth-View",
                    .outputTex = rc.depthViewTex.id,
                    .depthTex = rc.debugGridDepthTex.id,
                    .camBuf = rc.mainCamUB.id,
                });
            },
        }
    }
};
