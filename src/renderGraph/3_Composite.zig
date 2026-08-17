const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const CompositeNode = @import("../render/types/pass/RenderNode.zig").CompositeNode;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const OutputLoadData = @import("2_OutputLoad.zig").OutputLoadData;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const Viewport = @import("../viewport/Viewport.zig").Viewport;
const WindowId = @import("../.configs/idConfig.zig").WindowId;
const EngineData = @import("../EngineData.zig").EngineData;
const PassId = @import("../.configs/idConfig.zig").PassId;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const CompositeData = struct {
    passExtents: LinkedIdMap(struct { width: u32, height: u32 }, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    composites: FixedList(CompositeNode, rc.MAX_WINDOWS * 4) = .{},
};

pub const CompositeSys = struct {
    pub fn build(self: *CompositeData, outputLoad: *const OutputLoadData, registry: *const RenderRegistryData, data: *const EngineData) !void {
        self.composites.clear();
        self.passExtents.clear();

        // Check every Window
        for (data.window.activeWindows.constSlice()) |window| {
            // Check every Viewport
            for (window.viewIds) |viewId| {
                if (viewId) |viewportId| {
                    const viewport = data.viewport.viewports.getByKey(viewportId.val());

                    // Check every Composite String
                    for (viewport.outputTuples) |outputTuple| {
                        const outTexPassId = try registry.getTexturePassId(outputTuple.texName);
                        const outPassId = try registry.getPassId(outputTuple.passName);
                        const passDef = try registry.getPassDefinitionById(outPassId);

                        if (self.passExtents.isKeyUsed(outPassId) == false) self.passExtents.insert(outPassId, .{ .width = 0, .height = 0 });
                        const passExtent = self.passExtents.getPtrByKey(outPassId);

                        // Check for bigger Viewport Area:
                        const viewWidth = viewport.calcViewWidth(window.extent.width);
                        const scaledWidth = @as(f32, @floatFromInt(viewWidth)) * passDef.renderScaling;
                        const scaledWidthInt: u32 = @intFromFloat(scaledWidth);
                        if (scaledWidthInt > passExtent.width) passExtent.width = scaledWidthInt;

                        const viewHeight = viewport.calcViewHeight(window.extent.height);
                        const scaledHeight = @as(f32, @floatFromInt(viewHeight)) * passDef.renderScaling;
                        const scaledHeightInt: u32 = @intFromFloat(scaledHeight);
                        if (scaledHeightInt > passExtent.height) passExtent.height = scaledHeightInt;

                        // Check Blit or Composite
                        const composite = createComposite(&viewport, outPassId, outTexPassId, window.id, window.extent.width, window.extent.height);
                        self.composites.append(composite) catch std.debug.print("PassDef Could not Append Composite\n", .{});
                    }
                }
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("3.Composite: \n", .{});
            for (outputLoad.activePasses.getConstItems(), 0..) |passId, i| {
                const passName = try registry.getPassName(passId);
                if (self.passExtents.isKeyUsed(passId) == true) {
                    const passExtent = self.passExtents.getByKey(passId);
                    std.debug.print("- Pass {}. {s} (Size {} x {})\n", .{ i, passName, passExtent.width, passExtent.height });
                } else std.debug.print("- Pass {}. {s} (Size .NULL x .NULL)\n", .{ i, passName });
            }
            std.debug.print("\n", .{});
            for (self.composites.constSlice(), 0..) |comp, i| {
                const passName = try registry.getPassName(comp.pass);
                std.debug.print("- Composite {}. {s} (Pass {s}) [{}x{} @ {},{}]\n", .{ i, comp.name, passName, comp.viewWidth, comp.viewHeight, comp.viewOffsetX, comp.viewOffsetY });
            }
            std.debug.print("\n", .{});
        }
    }

    fn createComposite(viewport: *const Viewport, pass: PassId, outputTexPassId: TexPassId, windowId: WindowId, windowWidth: u32, windowHeight: u32) CompositeNode {
        return CompositeNode{
            .name = viewport.name,
            .pass = pass,
            .srcTexUnion = .{ .texPassId = outputTexPassId },
            .windowId = windowId,
            .viewWidth = viewport.calcViewWidth(windowWidth),
            .viewHeight = viewport.calcViewHeight(windowHeight),
            .viewOffsetX = viewport.calcViewX(windowWidth),
            .viewOffsetY = viewport.calcViewY(windowHeight),
            .opacity = viewport.opacity,
            .stretch = rc.COMPOSITE_TEX_STRETCH,
        };
    }
};
