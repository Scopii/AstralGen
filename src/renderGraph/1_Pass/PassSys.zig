const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const CompositeNode = @import("../../render/types/pass/RenderNode.zig").CompositeNode;
const PassInstance = @import("../../render/types/pass/PassInstance.zig").PassInstance;
const ViewportBlit = @import("../../render/types/pass/RenderNode.zig").ViewportBlit;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const WindowId = @import("../../.configs/idConfig.zig").WindowId;
const Viewport = @import("../../viewport/Viewport.zig").Viewport;
const EngineData = @import("../../EngineData.zig").EngineData;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const PassData = @import("PassData.zig").PassData;

// Step 1

pub const PassSys = struct {
    pub fn build(passData: *PassData, registry: *const RenderRegistryData, data: *const EngineData) !void {
        passData.activePasses.clear();
        passData.passExtents.clear();
        passData.composites.clear();
        passData.blits.clear();

        // Extracting all Unique Passes
        for (data.viewport.activeViewportIds.getConstItems()) |viewportId| {
            const viewport = data.viewport.viewports.getByKey(viewportId.val());

            for (viewport.stringPasses) |stringPass| {
                // Append PassId if Pass has Definition
                const hasDefinition = registry.passIdMap.contains(stringPass);
                if (hasDefinition == true) {
                    const passId = try registry.getPassId(stringPass);
                    passData.activePasses.upsert(passId, passId); // Map automatically filters duplicates
                }
            }
        }

        for (passData.activePasses.getConstItems()) |passId| {
            const passName = try registry.getPassName(passId);
            const passDef = try registry.getPassDefinition(passName);
            const passOutputTexDef = if (passDef.outputTex) |outputTex| try registry.getTexturePassId(outputTex) else null;

            var passWidth: u32 = 0;
            var passHeight: u32 = 0;

            if (passOutputTexDef) |outTexPassId| { // Skips logic if Pass has no Output
                // Active Windows
                for (data.window.activeWindows.constSlice()) |*window| {
                    // Window Viewports
                    for (window.viewIds) |windowViewId| {
                        if (windowViewId) |viewId| {
                            const viewport = data.viewport.viewports.getByKey(viewId.val());
                            var usedPass: ?[]const u8 = null;

                            for (viewport.stringPasses) |stringPass| {
                                if (std.mem.eql(u8, stringPass, passName)) {
                                    usedPass = stringPass;
                                    break; // Found it, stop searching this slice (FORCES NON REPEATING PASSES)
                                }
                            }

                            if (usedPass != null) {
                                // Check for bigger Viewport Area:
                                const viewWidth = viewport.calcViewWidth(window.extent.width);
                                if (viewWidth > passWidth) passWidth = viewWidth;

                                const viewHeight = viewport.calcViewHeight(window.extent.height);
                                if (viewHeight > passHeight) passHeight = viewHeight;

                                // Check Blit or Composite
                                if (viewport.blitPass) |usedBlit| {
                                    if (std.mem.eql(u8, passName, usedBlit)) {
                                        const blit = createBlit(&viewport, passId, outTexPassId, window.id, window.extent.width, window.extent.height);
                                        passData.blits.append(blit) catch std.debug.print("PassDef Could not Append Blit\n", .{});
                                        break;
                                    }
                                } else {
                                    const composite = createComposite(&viewport, passId, outTexPassId, window.id, window.extent.width, window.extent.height);
                                    passData.composites.append(composite) catch std.debug.print("PassDef Could not Append Composite\n", .{});
                                }
                            }
                        }
                    }
                }
            }

            if (passData.passExtents.isFull() == true) return error.RenderNodesFull;
            const scaledWidth = @as(f32, @floatFromInt(passWidth)) * passDef.renderScaling;
            const scaledHeight = @as(f32, @floatFromInt(passHeight)) * passDef.renderScaling;
            passData.passExtents.upsert(passId, .{ .width = @intFromFloat(scaledWidth), .height = @intFromFloat(scaledHeight) });
            if (rc.PASS_EXTRACTION_DEBUG) std.debug.print("Pass {s} added (width {} height {})\n", .{ passName, passWidth, passHeight });
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("1.PassExtractor: \n", .{});
            for (passData.activePasses.getConstItems(), 0..) |passId, i| {
                const passName = try registry.getPassName(passId);
                const passExtent = passData.passExtents.getByKey(passId);
                std.debug.print("- Pass {}. {s} (Size {} x {})\n", .{ i, passName, passExtent.width, passExtent.height });
            }
            for (passData.composites.constSlice(), 0..) |comp, i| {
                const passName = try registry.getPassName(comp.pass);
                std.debug.print("- Composite {}. {s} (Pass {s}) [{}x{} @ {},{}]\n", .{ i, comp.name, passName, comp.viewWidth, comp.viewHeight, comp.viewOffsetX, comp.viewOffsetY });
            }
            for (passData.blits.constSlice(), 0..) |blit, i| {
                std.debug.print("- Blit {}. {s} (Pass {s})\n", .{ i, blit.name, try registry.getPassName(blit.pass) });
            }
            std.debug.print("\n", .{});
        }
    }

    fn createBlit(viewport: *const Viewport, pass: PassId, outputTexPassId: TexPassId, windowId: WindowId, windowWidth: u32, windowHeight: u32) ViewportBlit {
        return ViewportBlit{
            .name = viewport.name,
            .pass = pass,
            .srcTexUnion = .{ .texPassId = outputTexPassId },
            .dstWindowId = windowId,
            .viewWidth = viewport.calcViewWidth(windowWidth),
            .viewHeight = viewport.calcViewHeight(windowHeight),
            .viewOffsetX = viewport.calcViewX(windowWidth),
            .viewOffsetY = viewport.calcViewY(windowHeight),
        };
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
            .stretch = rc.BLIT_TEX_STRETCH,
        };
    }

    pub fn getPassOutputTex(registry: *const RenderRegistryData, passName: []const u8) !?TexPassId {
        const passDef = try registry.getPassDefinition(passName);
        return if (passDef.outputTex) |outputTex| try registry.getTexturePassId(outputTex) else return null;
    }
};
