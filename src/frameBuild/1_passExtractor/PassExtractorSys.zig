const CompositeNode = @import("../../render/types/pass/RenderNode.zig").CompositeNode;
const PassInstance = @import("../../render/types/pass/PassInstance.zig").PassInstance;
const ViewportBlit = @import("../../render/types/pass/RenderNode.zig").ViewportBlit;
const WindowId = @import("../../window/Window.zig").Window.WindowId;
const Viewport = @import("../../viewport/Viewport.zig").Viewport;
const EngineData = @import("../../EngineData.zig").EngineData;
const rc = @import("../../.configs/renderConfig.zig");
const PassId = @import("../components.zig").PassId;
const TexPassId = @import("../components.zig").TexPassId;
const std = @import("std");

const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const PassExtractorData = @import("PassExtractorData.zig").PassExtractorData;

// Step 1

pub const PassExtractorSys = struct {
    pub fn newBuild(passExtractor: *PassExtractorData, resourceRegistry: *const ResourceRegistryData, data: *const EngineData) !void {
        // Cleanup
        passExtractor.activePasses.clear();
        passExtractor.passResolutions.clear();
        passExtractor.composites.clear();
        passExtractor.blits.clear();

        // Extracting all Unique Passes
        for (data.viewport.activeViewportIds.getConstItems()) |viewportId| {
            const viewport = data.viewport.viewports.getByKey(viewportId.val);

            for (viewport.stringPasses) |stringPass| {
                // Append PassId if Pass has Definition
                const passHasDefinition = resourceRegistry.passIdMap.contains(stringPass);
                if (passHasDefinition == true) {
                    const passId = try resourceRegistry.getPassId(stringPass);
                    passExtractor.activePasses.upsert(passId.val(), passId); // Map automatically filters duplicates
                }
            }
        }

        for (passExtractor.activePasses.getConstItems()) |passId| {
            const passString = try resourceRegistry.getPassName(passId);
            const possibleOutputTex = try getPassOutputTex(resourceRegistry, passString);
            var passWidth: u32 = 0;
            var passHeight: u32 = 0;

            if (possibleOutputTex) |outputTexPassId| { // Skips logic if Pass has no Output
                // Active Windows
                for (data.window.activeWindows.constSlice()) |*window| {
                    // Window Viewports
                    for (window.viewIds) |windowViewId| {
                        if (windowViewId) |viewId| {
                            const viewport = data.viewport.viewports.getByKey(viewId.val);
                            var usedPass: ?[]const u8 = null;

                            for (viewport.stringPasses) |stringPass| {
                                if (std.mem.eql(u8, stringPass, passString)) {
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
                                    if (std.mem.eql(u8, passString, usedBlit)) {
                                        const blit = createBlit(&viewport, passId, outputTexPassId, window.id, window.extent.width, window.extent.height);
                                        passExtractor.blits.append(blit) catch std.debug.print("PassDef Could not Append Blit\n", .{});
                                        break;
                                    }
                                } else {
                                    const composite = createComposite(&viewport, passId, outputTexPassId, window.id, window.extent.width, window.extent.height);
                                    passExtractor.composites.append(composite) catch std.debug.print("PassDef Could not Append Composite\n", .{});
                                }
                            }
                        }
                    }
                }
            }

            if (passExtractor.passResolutions.isFull() == true) return error.RenderNodesFull;
            passExtractor.passResolutions.upsert(passId.val(), .{ .width = passWidth, .height = passHeight });
            if (rc.PASS_EXTRACTION_DEBUG) std.debug.print("Pass {s} added (width {} height {})\n", .{ passString, passWidth, passHeight });
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("1.PassExtractor: \n", .{});
            for (passExtractor.activePasses.getConstItems(), 0..) |passId, i| {
                const passCoreName = try resourceRegistry.getPassName(passId);
                std.debug.print("- Pass {}. {s}\n", .{ i, passCoreName });
            }
            for (passExtractor.composites.constSlice(), 0..) |composite, i| {
                std.debug.print("- Composite {}. {s} (Pass {s})\n", .{ i, composite.name, try resourceRegistry.getPassName(composite.pass) });
            }
            for (passExtractor.blits.constSlice(), 0..) |blit, i| {
                std.debug.print("- Blit {}. {s} (Pass {s})\n", .{ i, blit.name, try resourceRegistry.getPassName(blit.pass) });
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
            .stretch = rc.RENDER_TEX_STRETCH,
        };
    }

    pub fn getPassOutputTex(resourceRegistry: *const ResourceRegistryData, passName: []const u8) !?TexPassId {
        const passDef = try resourceRegistry.getPassDefinition(passName);
        return if (passDef.outputTex) |outputTex| try resourceRegistry.getTexturePassId(outputTex) else return null;
    }
};
