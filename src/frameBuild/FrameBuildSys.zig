const ViewportBlit = @import("../render/types/base/Pass.zig").ViewportBlit;
const ViewportId = @import("../viewport/ViewportSys.zig").ViewportId;
const FrameBuildData = @import("FrameBuildData.zig").FrameBuildData;
const WindowId = @import("../window/Window.zig").Window.WindowId;
const Viewport = @import("../viewport/Viewport.zig").Viewport;
const EngineData = @import("../EngineData.zig").EngineData;
const Pass = @import("../render/types/base/Pass.zig").Pass;
const pDef = @import("../.configs/passConfig.zig");
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const PassStruct = packed struct {
    CompTest: bool = false,
    CullComp: bool = false,
    CullMain: bool = false,
    CullDebug: bool = false,
    QuantComp: bool = false,
    QuantGridMain: bool = false,
    QuantGridDebug: bool = false,
    EditorGrid: bool = false,
    QuantPlaneMain: bool = false,
    QuantPlaneDebug: bool = false,
    FrustumView: bool = false,
};

pub const PassEnum = enum {
    ENTRY, // Not an actual Pass
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
    EXIT, // Not an actual Pass
};

pub const FrameBuildSys = struct {
    pub fn build(frameBuild: *FrameBuildData, data: *const EngineData) void {
        const activeViewportIds = data.viewport.activeViewportIds.constSlice();
        var passMask: PassStruct = .{};

        frameBuild.passList.clear();

        // Fill Pass Mask
        inline for (@typeInfo(PassStruct).@"struct".fields) |field| {
            for (activeViewportIds) |viewportId| {
                const viewport = data.viewport.viewports.getByKey(viewportId.val);
                const viewMaskValue = @field(viewport.passMask, field.name);

                if (viewMaskValue == true) {
                    @field(passMask, field.name) = true;
                    if (rc.FRAME_BUILD_DEBUG) std.debug.print("Viewport ({s}) demanded {s}\n", .{ viewport.name, field.name });
                    break;
                }
            }
        }

        const activeWindows = data.window.activeWindows.constSlice();

        // Launch Passes and Blits for filled Mask
        inline for (@typeInfo(PassStruct).@"struct".fields) |field| {
            if (@field(passMask, field.name) == true) {
                const passEnum = @field(PassEnum, field.name);

                var passWidth: u32 = 0;
                var passHeight: u32 = 0;

                // Check Maximum View of Pass
                for (activeViewportIds) |viewportId| {
                    const viewport = data.viewport.viewports.getByKey(viewportId.val);

                    const isPassDemanded = @field(viewport.passMask, field.name);

                    if (isPassDemanded) {
                        for (activeWindows) |*window| {
                            var isAttached = false;
                            for (window.viewIds) |windowViewId| {
                                if (windowViewId != null and windowViewId.?.val == viewportId.val) {
                                    isAttached = true;
                                    break;
                                }
                            }

                            if (isAttached) {
                                const viewWidth = viewport.calcViewWidth(window.extent.width);
                                const viewHeight = viewport.calcViewHeight(window.extent.height);

                                if (viewWidth > passWidth) {
                                    passWidth = viewWidth;
                                    // if (rc.FRAME_BUILD_DEBUG) std.debug.print("{s} set Pass Width to {}\n", .{ viewport.name, viewWidth });
                                }
                                if (viewHeight > passHeight) {
                                    passHeight = viewHeight;
                                    // if (rc.FRAME_BUILD_DEBUG) std.debug.print("{s} set Pass Height to {}\n", .{ viewport.name, viewHeight });
                                }
                            }
                        }
                    }
                }

                appendPass(frameBuild, passEnum, passWidth, passHeight) catch std.debug.print("ERROR: COULD NOT APPEND PASS\n", .{});
                if (rc.FRAME_BUILD_DEBUG) std.debug.print("Pass {s} added (width {} height {})\n", .{ field.name, passWidth, passHeight });

                // Check for Blits
                for (activeViewportIds) |viewportId| {
                    const viewport = data.viewport.viewports.getByKey(viewportId.val);

                    if (viewport.blitPass == passEnum) {
                        for (activeWindows) |*window| {
                            var isAttached = false;
                            for (window.viewIds) |windowViewId| {
                                if (windowViewId != null and windowViewId.?.val == viewportId.val) {
                                    isAttached = true;
                                    break;
                                }
                            }

                            if (isAttached) {
                                appendBlit(frameBuild, &viewport, window.id, window.extent.width, window.extent.height);
                            }
                        }
                    }
                }
            }
        }
    }

    fn appendBlit(frameBuild: *FrameBuildData, viewport: *const Viewport, windowId: WindowId, windowWidth: u32, windowHeight: u32) void {
        const blitNode = ViewportBlit{
            .name = viewport.name,
            .srcTexId = viewport.sourceTexId,
            .dstWindowId = windowId,
            .viewWidth = viewport.calcViewWidth(windowWidth),
            .viewHeight = viewport.calcViewHeight(windowHeight),
            .viewOffsetX = viewport.calcViewX(windowWidth),
            .viewOffsetY = viewport.calcViewY(windowHeight),
        };
        frameBuild.passList.append(.{ .viewportBlit = blitNode }) catch std.debug.print("Pass Could not Append Blit\n", .{});
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
            .ENTRY, .EXIT => {},
        }
    }
};
