const ResourceAssignerData = @import("../6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData;
const GraphExtractorData = @import("../4_graphExtractor/GraphExtractorData.zig").GraphExtractorData;
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
        graphExtractor: *const GraphExtractorData,
        groupMerger: *const GroupMergerData,
        resourceAssigner: *const ResourceAssignerData,
    ) !void {
        passSorter.tempPasses.clear();
        passSorter.tempBlits.clear();
        passSorter.tempComposites.clear();
        passSorter.tempUi.clear();

        passSorter.sortedRenderNodes.clear();
        const renderNodes = passExtractor.renderNodes.constSlice();

        // Sort into Buckets
        for (renderNodes, 0..) |*renderNode, i| {
            switch (renderNode.*) {
                .passNode => passSorter.tempPasses.append(@intCast(i)) catch std.debug.print("7.PassSorter: Failed to append Pass", .{}),
                .viewportBlit => passSorter.tempBlits.append(@intCast(i)) catch std.debug.print("7.PassSorter: Failed to append Blit", .{}),
                .compositeNode => passSorter.tempComposites.append(@intCast(i)) catch std.debug.print("7.PassSorter: Failed to append Composite", .{}),
                .uiNode => passSorter.tempUi.append(@intCast(i)) catch std.debug.print("7.PassSorter: Failed to append UI", .{}),
                else => {}, // clears/barriers generated below
            }
        }

        // Check Buckets for Correct Pass
        for (graphExtractor.orderedPasses.getConstItems()) |graphNode| {
            const passEnum = graphNode.passEnum;

            var neededClears = false;
            // Buffer Clears
            for (groupMerger.bufClears.constSlice()) |bufClear| {
                if (bufClear.passAfterClear == passEnum) {
                    // LOOKUP FOR bufClear.Index to ENUM!
                    const bufId = resourceAssigner.usedTransientBufs.buffer[bufClear.sharedBufIndex].bufId;
                    try passSorter.sortedRenderNodes.append(.{ .clearBuffer = bufId });
                    neededClears = true;
                }
            }
            // Texture Clears
            for (groupMerger.texClears.constSlice()) |texClear| {
                if (texClear.passAfterClear == passEnum) {
                    // LOOKUP FOR texClear.Index to ENUM!
                    const texId = resourceAssigner.usedTransientTexes.buffer[texClear.sharedTexIndex].texId;
                    try passSorter.sortedRenderNodes.append(.{ .clearTexture = texId });
                    neededClears = true;
                }
            }
            // Call for Clear Barrier baking if needed
            if (neededClears) try passSorter.sortedRenderNodes.append(.barrierBakeClears);

            // Passes
            for (passSorter.tempPasses.constSlice()) |i| {
                const pass = &renderNodes[i].passNode;
                if (pass.pass.name == passEnum) {
                    passSorter.sortedRenderNodes.append(.{ .passNode = pass.* }) catch std.debug.print("7.PassSorter: Pass Append to sortedRenderNodes failed", .{});
                }
            }
            // Blits
            for (passSorter.tempBlits.constSlice()) |i| {
                const blit = &renderNodes[i].viewportBlit;
                if (blit.pass == passEnum) {
                    passSorter.sortedRenderNodes.append(.{ .viewportBlit = blit.* }) catch std.debug.print("7.PassSorter: Blit Append to sortedRenderNodes failed", .{});
                }
            }
            // Composites
            for (passSorter.tempComposites.constSlice()) |i| {
                const composite = &renderNodes[i].compositeNode;
                if (composite.pass == passEnum) {
                    passSorter.sortedRenderNodes.append(.{ .compositeNode = composite.* }) catch std.debug.print("7.PassSorter: Composite Append to sortedRenderNodes failed", .{});
                }
            }
        }

        // Ui
        for (passSorter.tempUi.constSlice()) |i| {
            passSorter.sortedRenderNodes.append(.{ .uiNode = renderNodes[i].uiNode }) catch std.debug.print("7.PassSorter: Ui Append to sortedRenderNodes failed", .{});
        }

        // Debug Prints
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("7.PassSorter:\n", .{});
            for (passSorter.sortedRenderNodes.constSlice(), 0..) |*renderNode, i| {
                switch (renderNode.*) {
                    .passNode => |*pass| std.debug.print("- {}. Pass: {s}\n", .{ i, @tagName(pass.pass.name) }),
                    .compositeNode => |*composite| std.debug.print("- {}. Composite: {s} (Pass {})\n", .{ i, composite.name, composite.pass }),
                    .viewportBlit => |*blit| std.debug.print("- {}. Blit: {s} (Pass {})\n", .{ i, blit.name, blit.pass }),
                    .uiNode => |*ui| std.debug.print("- {}. UI: {s} (WindowID {})\n", .{ i, ui.name, ui.windowId }),
                    .clearBuffer => |*clearBuf| std.debug.print("- {}. ClearBuffer: {}\n", .{ i, clearBuf.* }),
                    .clearTexture => |*clearTex| std.debug.print("- {}. ClearTexture: {}\n", .{ i, clearTex.* }),
                    .barrierBakeClears => std.debug.print("- {}. Bake Clears\n", .{i}),
                }
            }
            std.debug.print("\n", .{});
        }
    }
};
