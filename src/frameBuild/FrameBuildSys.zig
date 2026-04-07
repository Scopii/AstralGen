const FrameBuildData = @import("FrameBuildData.zig").FrameBuildData;
const EngineData = @import("../EngineData.zig").EngineData;
const std = @import("std");
const pDef = @import("../.configs/passConfig.zig");
const rc = @import("../.configs/renderConfig.zig");
const ViewportId = @import("../viewport/ViewportSys.zig").ViewportId;
const Pass = @import("../render/types/base/Pass.zig").Pass;
const ViewportBlit = @import("../render/types/base/Pass.zig").ViewportBlit;

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
    ENTRY,
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
    EXIT,
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
                appendPass(frameBuild, passEnum) catch std.debug.print("ERROR: COULD NOT APPEND PASS\n", .{});
                if (rc.FRAME_BUILD_DEBUG) std.debug.print("Pass {s} added\n", .{field.name});

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
                                const viewArea2D = viewport.calcViewArea(window.extent.width, window.extent.height);
                                const viewOffset2D = viewport.calcViewOffset(window.extent.width, window.extent.height);

                                const blitNode = ViewportBlit{
                                    .name = viewport.name,
                                    .srcTexId = viewport.sourceTexId,
                                    .dstWindowId = window.id,
                                    .viewWidth = viewArea2D.width,
                                    .viewHeight = viewArea2D.height,
                                    .viewOffsetX = viewOffset2D.x,
                                    .viewOffsetY = viewOffset2D.y,
                                };

                                frameBuild.passList.append(.{ .viewportBlit = blitNode }) catch std.debug.print("Pass Could not Append\n", .{});
                            }
                        }
                    }
                }
            }
        }
    }

    fn appendPass(frameBuild: *FrameBuildData, passEnum: PassEnum) !void {
        switch (passEnum) {
            .CompTest => {
                const pass = pDef.CompRayMarch(.{
                    .name = "CompTest",
                    .entityBuf = rc.entitySB.id,
                    .outputTex = rc.mainTex.id,
                    .camBuf = rc.mainCamUB.id,
                    .readbackBuf = rc.readbackSB.id,
                });
                try frameBuild.passList.append(.{ .pass = pass });
            },
            .CullComp => {
                const pass = pDef.CullComp(.{
                    .name = "Cull-Comp",
                    .indirectBuf = rc.indirectSB.id,
                    .entityBuf = rc.entitySB.id,
                });
                try frameBuild.passList.append(.{ .pass = pass });
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
                try frameBuild.passList.append(.{ .pass = pass });
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
                try frameBuild.passList.append(.{ .pass = pass });
            },
            .QuantComp => {
                const pass = pDef.QuantComp(.{
                    .name = "Quant-Comp",
                    .indirectBuf = rc.indirectSB.id,
                    .entityBuf = rc.entitySB.id,
                });
                try frameBuild.passList.append(.{ .pass = pass });
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
                try frameBuild.passList.append(.{ .pass = pass });
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
                try frameBuild.passList.append(.{ .pass = pass });
            },
            .EditorGrid => {
                const pass = pDef.EditorGrid(.{
                    .name = "Editor-Grid",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .camBuf = rc.debugCamUB.id,
                });
                try frameBuild.passList.append(.{ .pass = pass });
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
                try frameBuild.passList.append(.{ .pass = pass });
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
                try frameBuild.passList.append(.{ .pass = pass });
            },
            .FrustumView => {
                const pass = pDef.FrustumView(.{
                    .name = "FrustumView",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .frustumCamBuf = rc.mainCamUB.id,
                    .viewCamBuf = rc.debugCamUB.id,
                });
                try frameBuild.passList.append(.{ .pass = pass });
            },
            .ENTRY, .EXIT => {},
        }
    }
};
