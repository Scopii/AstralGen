const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const PassData = @import("../1_Pass/PassData.zig").PassData;
const OptimizerData = @import("../4.5_Optimizer/OptimizerData.zig").OptimizerData;
const GroupData = @import("../5.4_Group/GroupData.zig").GroupData;
const SorterData = @import("../7_Sorter/SorterData.zig").SorterData;

// Step 7

pub const SorterSys = struct {
    pub fn build(sorterData: *SorterData, passData: *const PassData, optimizerData: *const OptimizerData, groupData: *const GroupData, registry: *const RenderRegistryData) !void {
        sorterData.sortedRenderIR.clear();

        // Check Buckets for Correct Pass
        for (optimizerData.optimizedGraph.getConstItems()) |graphNode| {
            const passId = graphNode.pass;

            // Resource Clears
            var neededClears = false;

            for (groupData.bufClears.constSlice()) |bufClear| {
                if (bufClear.passAfterClear == passId) {
                    try sorterData.sortedRenderIR.append(.{ .clearBufIR = bufClear.rootResource });
                    neededClears = true;
                }
            }
            for (groupData.texClears.constSlice()) |texClear| {
                if (texClear.passAfterClear == passId) {
                    try sorterData.sortedRenderIR.append(.{ .clearTexIR = texClear.rootResource });
                    neededClears = true;
                }
            }
            if (neededClears) try sorterData.sortedRenderIR.append(.barrierBakeClears); // Call for Clear Barrier baking if needed

            // Passes
            sorterData.sortedRenderIR.append(.{ .passIR = passId }) catch std.debug.print("7.PassSorter: Pass Append to sortedRenderNodes failed", .{});

            // Composites
            for (passData.composites.constSlice()) |composite| {
                if (composite.pass == passId) {
                    sorterData.sortedRenderIR.append(.{ .compositeIR = composite }) catch std.debug.print("7.PassSorter: Composite Append to sortedRenderNodes failed", .{});
                }
            }
        }

        // Debug Prints
        if (rc.FRAME_GRAPH_DEBUG or rc.FRAME_GRAPH_SORT_DEBUG) {
            std.debug.print("7.PassSorter:\n", .{});
            for (sorterData.sortedRenderIR.constSlice(), 0..) |renderNode, index| {
                switch (renderNode) {
                    .passIR => |passId| std.debug.print("- {}. Pass: {}\n", .{ index, passId.val() }),
                    .compositeIR => |composite| std.debug.print("- {}. Composite: {s} (Pass {s})\n", .{ index, composite.name, try registry.getPassName(composite.pass) }),
                    .clearBufIR => |clearBuf| std.debug.print("- {}. ClearBuffer: BufPassId {}\n", .{ index, clearBuf.val() }),
                    .clearTexIR => |clearTex| std.debug.print("- {}. ClearTexture: TexPassId {}\n", .{ index, clearTex.val() }),
                    .barrierBakeClears => std.debug.print("- {}. Bake Clears\n", .{index}),
                }
            }
            std.debug.print("\n", .{});
        }
    }
};
