const ViewportBlit = @import("../render/types/pass/PassDef.zig").ViewportBlit;
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
    CompTest,
    CullComp,
    CullMain,
    CullDebug,
    QuantComp,
    QuantGridMain,
    QuantGridDebug,
    EditorGrid,
    QuantPlaneMain,
    QuantPlaneDebug,
    FrustumView,
};

pub const FrameBuildSys = struct {
    pub fn build(frameBuild: *FrameBuildData, data: *const EngineData) void {
        const activeViewportIds = data.viewport.activeViewportIds.constSlice();

        const passEnumFields = @typeInfo(PassEnum).@"enum".fields;
        var passMask: [passEnumFields.len]bool = .{false} ** passEnumFields.len;

        frameBuild.passList.clear();

        // Check every Viewports Pass Order and set passMask
        for (activeViewportIds) |viewportId| {
            const viewport = data.viewport.viewports.getByKey(viewportId.val);
            var lastViewPassEnum: ?PassEnum = null;

            for (0..viewport.passSlice.len) |i| {
                const viewPassEnum = viewport.passSlice[i];
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
        var tempBlits: FixedList(ViewportBlit, rc.MAX_WINDOWS * 4) = .{};

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
                            for (viewport.passSlice) |viewPassEnum| {
                                if (viewPassEnum == passMaskEnum) {
                                    usesPass = true;
                                    break; // Found it, stop searching this slice
                                }
                            }

                            // Check if Viewport:
                            if (usesPass) {
                                if (passMaskEnum == viewport.blitPass) {
                                    const blit = createBlit(&viewport, window.id, window.extent.width, window.extent.height);
                                    tempBlits.append(blit) catch std.debug.print("PassDef Could not Append Blit\n", .{});
                                }
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
                                break;
                            }
                        }
                    }
                }

                appendPass(frameBuild, passMaskEnum, passWidth, passHeight) catch std.debug.print("ERROR: COULD NOT APPEND PASS\n", .{});
                if (rc.FRAME_BUILD_DEBUG) std.debug.print("Pass {s} added (width {} height {})\n", .{ @enumFromInt(passIndex), passWidth, passHeight });

                for (tempBlits.constSlice()) |blit| {
                    frameBuild.passList.append(.{ .viewportBlit = blit }) catch std.debug.print("PassDef Could not Append Blit\n", .{});
                }
                tempBlits.clear();
            }
        }
    }

    fn createBlit(viewport: *const Viewport, windowId: WindowId, windowWidth: u32, windowHeight: u32) ViewportBlit {
        const blitNode = ViewportBlit{
            .name = viewport.name,
            .srcTexId = viewport.sourceTexId,
            .dstWindowId = windowId,
            .viewWidth = viewport.calcViewWidth(windowWidth),
            .viewHeight = viewport.calcViewHeight(windowHeight),
            .viewOffsetX = viewport.calcViewX(windowWidth),
            .viewOffsetY = viewport.calcViewY(windowHeight),
        };
        return blitNode;
    }

    fn appendPass(frameBuild: *FrameBuildData, passEnum: PassEnum, passWidth: u32, passHeight: u32) !void {
        switch (passEnum) {
            .CompTest => {
                const pass = pDef.CompRayMarch(.{
                    .name = "Compute-Ray-March",
                    .entityBuf = rc.entitySB.id,
                    .outputTex = rc.mainTex.id,
                    .camBuf = rc.mainCamUB.id,
                    .readbackBuf = rc.readbackSB.id,
                });
                try frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            },
            .CullComp => {
                const pass = pDef.CullComp(.{
                    .name = "Cull-Comp",
                    .indirectBuf = rc.indirectSB.id,
                    .entityBuf = rc.entitySB.id,
                });
                try frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            },
            .CullMain => {
                const pass = pDef.Cull(.{
                    .name = "Cull-Main",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.mainCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
                try frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            },
            .CullDebug => {
                const pass = pDef.Cull(.{
                    .name = "Cull-Debug",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.debugCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
                try frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            },
            .QuantComp => {
                const pass = pDef.QuantComp(.{
                    .name = "Quant-Comp",
                    .indirectBuf = rc.indirectSB.id,
                    .entityBuf = rc.entitySB.id,
                });
                try frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            },
            .QuantGridMain => {
                const pass = pDef.QuantGrid(.{
                    .name = "QuantGrid-Main",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.mainCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
                try frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            },
            .QuantGridDebug => {
                const pass = pDef.QuantGrid(.{
                    .name = "QuantGrid-Debug",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.debugCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
                try frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            },
            .EditorGrid => {
                const pass = pDef.EditorGrid(.{
                    .name = "Editor-Grid",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .camBuf = rc.debugCamUB.id,
                });
                try frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            },
            .QuantPlaneMain => {
                const pass = pDef.QuantPlane(.{
                    .name = "QuantPlane-Main",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.mainCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
                try frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            },
            .QuantPlaneDebug => {
                const pass = pDef.QuantPlane(.{
                    .name = "QuantPlane-Debug",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .indirectBuf = rc.indirectSB.id,
                    .viewCam = rc.debugCamUB.id,
                    .cullCam = rc.mainCamUB.id,
                });
                try frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            },
            .FrustumView => {
                const pass = pDef.FrustumView(.{
                    .name = "FrustumView",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .frustumCamBuf = rc.mainCamUB.id,
                    .viewCamBuf = rc.debugCamUB.id,
                });
                try frameBuild.passList.append(.{ .passNode = .{ .pass = pass, .width = passWidth, .height = passHeight } });
            },
        }
    }
};
