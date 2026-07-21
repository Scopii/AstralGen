const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const CompositeNode = @import("../../render/types/pass/RenderNode.zig").CompositeNode;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const WindowId = @import("../../.configs/idConfig.zig").WindowId;
const Viewport = @import("../../viewport/Viewport.zig").Viewport;
const EngineData = @import("../../EngineData.zig").EngineData;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const OutputData = @import("../0.5_Output/OutputData.zig").OutputData;
const PassData = @import("PassData.zig").PassData;

// Step 1

pub const PassSys = struct {
    pub fn build(passData: *PassData, output: *const OutputData, registry: *const RenderRegistryData, data: *const EngineData) !void {
        passData.composites.clear();
        passData.newPassExtents.clear();

        // Check every Window
        for (data.window.activeWindows.constSlice()) |window| {
            // Check every Viewport
            for (window.viewIds) |viewId| {
                if (viewId) |viewportId| {
                    const viewport = data.viewport.viewports.getByKey(viewportId.val());

                    // Check every Composite String
                    for (viewport.stringComposites) |stringComposite| {
                        const outTexPassId = try registry.getTexturePassId(stringComposite);
                        if (output.texProducer.isKeyUsed(outTexPassId) == false) return error.viewportCompositeTexHasNoProducer;
                        const producerPassId = output.texProducer.getByKey(outTexPassId);
                        const passDef = try registry.getPassDefinitionById(producerPassId);

                        if (passData.newPassExtents.isKeyUsed(producerPassId) == false) {
                            passData.newPassExtents.upsert(producerPassId, .{ .width = 0, .height = 0 });
                        }

                        const passExtent = passData.newPassExtents.getPtrByKey(producerPassId);

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
                        const composite = createComposite(&viewport, producerPassId, outTexPassId, window.id, window.extent.width, window.extent.height);
                        passData.composites.append(composite) catch std.debug.print("PassDef Could not Append Composite\n", .{});
                    }
                }
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("1.PassExtractor: \n", .{});
            for (output.activePasses.getConstItems(), 0..) |passId, i| {
                const passName = try registry.getPassName(passId);
                if (passData.newPassExtents.isKeyUsed(passId) == true) {
                    const passExtent = passData.newPassExtents.getByKey(passId);
                    std.debug.print("- Pass {}. {s} (Size {} x {})\n", .{ i, passName, passExtent.width, passExtent.height });
                } else std.debug.print("- Pass {}. {s} (Size .NULL x .NULL)\n", .{ i, passName });
            }
            std.debug.print("\n", .{});
            for (passData.composites.constSlice(), 0..) |comp, i| {
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

    pub fn getPassOutputTex(registry: *const RenderRegistryData, passName: []const u8) !?TexPassId {
        const passDef = try registry.getPassDefinition(passName);
        return if (passDef.outputTex) |outputTex| try registry.getTexturePassId(outputTex) else return null;
    }
};
