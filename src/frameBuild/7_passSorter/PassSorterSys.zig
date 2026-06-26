const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const ResourceAssignerData = @import("../6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData;
const GraphOptimizerData = @import("../4.5_graphOptimizer/GraphOptimizerData.zig").GraphOptimizerData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;
const GroupMergerData = @import("../5.4_groupMerger/GroupMergerData.zig").GroupMergerData;
const PassSorterData = @import("../7_passSorter/PassSorterData.zig").PassSorterData;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

// Step 7

pub const PassSorterSys = struct {
    pub fn buildFrame(
        passSorter: *PassSorterData,
        passExtractor: *const PassExtractorData,
        graphOptimizer: *const GraphOptimizerData,
        groupMerger: *const GroupMergerData,
        resourceAssigner: *const ResourceAssignerData,
        resourceRegistry: *const ResourceRegistryData,
    ) !void {
        passSorter.tempPasses.clear();
        passSorter.tempBlits.clear();
        passSorter.tempComposites.clear();

        passSorter.sortedRenderNodes.clear();
        const renderNodes = passExtractor.renderNodes.getConstItems();

        // Sort into Buckets
        for (renderNodes, 0..) |*renderNode, i| {
            switch (renderNode.*) {
                .passNode => passSorter.tempPasses.append(@intCast(i)) catch std.debug.print("7.PassSorter: Failed to append Pass", .{}),
                .viewportBlit => passSorter.tempBlits.append(@intCast(i)) catch std.debug.print("7.PassSorter: Failed to append Blit", .{}),
                .compositeNode => passSorter.tempComposites.append(@intCast(i)) catch std.debug.print("7.PassSorter: Failed to append Composite", .{}),
                .uiNode => return error.UiInPassSorter,
                else => {}, // clears/barriers generated below
            }
        }

        // Check Buckets for Correct Pass
        for (graphOptimizer.optimizedGraph.getConstItems()) |graphNode| {
            const passId = graphNode.pass;

            var neededClears = false;
            // Buffer Clears
            for (groupMerger.bufClears.constSlice()) |bufClear| {
                if (bufClear.passAfterClear.val() == passId.val()) {
                    // LOOKUP FOR bufClear.Index to ENUM!
                    const bufId = resourceAssigner.usedTransientBufs.buffer[bufClear.sharedBufIndex].hardwareBuf;
                    try passSorter.sortedRenderNodes.append(.{ .clearBuffer = bufId });
                    neededClears = true;
                }
            }
            // Texture Clears
            for (groupMerger.texClears.constSlice()) |texClear| {
                if (texClear.passAfterClear.val() == passId.val()) {
                    // LOOKUP FOR texClear.Index to ENUM!
                    const texId = resourceAssigner.usedTransientTexes.buffer[texClear.sharedTexIndex].hardwareTex;
                    try passSorter.sortedRenderNodes.append(.{ .clearTexture = texId });
                    neededClears = true;
                }
            }
            // Call for Clear Barrier baking if needed
            if (neededClears) try passSorter.sortedRenderNodes.append(.barrierBakeClears);

            // Passes
            for (passSorter.tempPasses.constSlice()) |i| {
                const key = passExtractor.renderNodes.getKeyByIndex(@intCast(i));
                if (key == passId.val()) {
                    const pass = &renderNodes[i].passNode;
                    passSorter.sortedRenderNodes.append(.{ .passNode = pass.* }) catch std.debug.print("7.PassSorter: Pass Append to sortedRenderNodes failed", .{});
                }
            }
            // Blits
            for (passSorter.tempBlits.constSlice()) |i| {
                const blit = &renderNodes[i].viewportBlit;
                if (blit.pass.val() == passId.val()) {
                    passSorter.sortedRenderNodes.append(.{ .viewportBlit = blit.* }) catch std.debug.print("7.PassSorter: Blit Append to sortedRenderNodes failed", .{});
                }
            }
            // Composites
            for (passSorter.tempComposites.constSlice()) |i| {
                const composite = &renderNodes[i].compositeNode;
                if (composite.pass.val() == passId.val()) {
                    passSorter.sortedRenderNodes.append(.{ .compositeNode = composite.* }) catch std.debug.print("7.PassSorter: Composite Append to sortedRenderNodes failed", .{});
                }
            }
        }

        // Debug Prints
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("7.PassSorter:\n", .{});
            for (passSorter.sortedRenderNodes.constSlice(), 0..) |*renderNode, index| {
                switch (renderNode.*) {
                    .passNode => |*passNode| std.debug.print("- {}. Pass: {s}\n", .{ index, passNode.pass.getName() }),
                    .compositeNode => |*composite| std.debug.print("- {}. Composite: {s} (Pass {s})\n", .{ index, composite.name, try resourceRegistry.getPassName(composite.pass) }),
                    .viewportBlit => |*blit| std.debug.print("- {}. Blit: {s} (Pass {s})\n", .{ index, blit.name, try resourceRegistry.getPassName(blit.pass) }),
                    .uiNode => |*ui| std.debug.print("- {}. UI: {s} (WindowID {})\n", .{ index, ui.name, ui.windowId }),
                    .clearBuffer => |*clearBuf| std.debug.print("- {}. ClearBuffer: {}\n", .{ index, clearBuf.* }),
                    .clearTexture => |*clearTex| std.debug.print("- {}. ClearTexture: {}\n", .{ index, clearTex.* }),
                    .barrierBakeClears => std.debug.print("- {}. Bake Clears\n", .{index}),
                }
            }
            std.debug.print("\n", .{});
        }
    }
};
