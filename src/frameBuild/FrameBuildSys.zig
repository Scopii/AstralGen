const FrameBuildData = @import("FrameBuildData.zig").FrameBuildData;
const EngineData = @import("../EngineData.zig").EngineData;
const std = @import("std");
const pDef = @import("../.configs/passConfig.zig");
const rc = @import("../.configs/renderConfig.zig");
const ViewportId = @import("../viewport/ViewportSys.zig").ViewportId;
const Pass = @import("../render/types/base/Pass.zig").Pass;

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

        inline for (@typeInfo(PassStruct).@"struct".fields) |field| {
            if (@field(passMask, field.name) == true) {
                const passEnum = @field(PassEnum, field.name);
                appendPass(frameBuild, passEnum) catch std.debug.print("ERROR: COULD NOT APPEND PASS\n", .{});
                if (rc.FRAME_BUILD_DEBUG)  std.debug.print("Pass {s} added\n", .{field.name});

                for (activeViewportIds) |viewportId| {
                    const viewport = data.viewport.viewports.getByKey(viewportId.val);

                    if (viewport.blitPass == passEnum) {
                        appendBlit(frameBuild, viewportId, viewport.name);
                        if (rc.FRAME_BUILD_DEBUG)  std.debug.print("blits to Viewport {s}\n", .{viewport.name});
                    }
                }
            }
        }

        // std.debug.print("WHOLE PASS SEQUENCE: \n", .{});
        // for (frameBuild.passList.constSlice()) |pass| {
        //     std.debug.print("{s} {s}\n", .{ @tagName(pass.execution), pass.name });
        // }
    }

    fn appendBlit(frameBuild: *FrameBuildData, viewportId: ViewportId, viewportName: []const u8) void {
        const blitPass = Pass.init(.{ .name = viewportName, .execution = .{ .viewportBlit = viewportId }, .shaderIds = &.{} });
        frameBuild.passList.append(blitPass) catch std.debug.print("Pass Could not Append\n", .{});
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
                try frameBuild.passList.append(pass);
            },
            .CullComp => {
                const pass = pDef.CullComp(.{
                    .name = "Cull-Comp",
                    .indirectBuf = rc.indirectSB.id,
                    .entityBuf = rc.entitySB.id,
                });
                try frameBuild.passList.append(pass);
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
                try frameBuild.passList.append(pass);
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
                try frameBuild.passList.append(pass);
            },
            .QuantComp => {
                const pass = pDef.QuantComp(.{
                    .name = "Quant-Comp",
                    .indirectBuf = rc.indirectSB.id,
                    .entityBuf = rc.entitySB.id,
                });
                try frameBuild.passList.append(pass);
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
                try frameBuild.passList.append(pass);
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
                try frameBuild.passList.append(pass);
            },
            .EditorGrid => {
                const pass = pDef.EditorGrid(.{
                    .name = "Editor-Grid",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .camBuf = rc.debugCamUB.id,
                });
                try frameBuild.passList.append(pass);
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
                try frameBuild.passList.append(pass);
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
                try frameBuild.passList.append(pass);
            },
            .FrustumView => {
                const pass = pDef.FrustumView(.{
                    .name = "FrustumView",
                    .colorAtt = rc.mainTex.id,
                    .depthAtt = rc.mainDepthTex.id,
                    .frustumCamBuf = rc.mainCamUB.id,
                    .viewCamBuf = rc.debugCamUB.id,
                });
                try frameBuild.passList.append(pass);
            },
            .ENTRY, .EXIT => {},
        }
    }
};
