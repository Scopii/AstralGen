const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const RenderNodeIR = @import("../../render/types/pass/RenderNode.zig").RenderNodeIR;
const CompositeData = @import("../3_Composite/Composite.zig").CompositeData;
const OptimizerData = @import("../6_Optimizer/Optimizer.zig").OptimizerData;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const ShareData = @import("../8_Share/Share.zig").ShareData;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

pub const SorterData = struct {
    sortedRenderIR: FixedList(RenderNodeIR, rc.PASS_MAX + rc.MAX_WINDOWS * 4) = .{},
};

pub const SorterSys = struct {
    pub fn build(self: *SorterData, compositeData: *const CompositeData, optimizer: *const OptimizerData, registry: *const RenderRegistryData, share: *const ShareData) !void {
        self.sortedRenderIR.clear();

        // Check Buckets for Correct Pass
        for (optimizer.optimizedGraph.getConstItems()) |graphNode| {
            const passId = graphNode.passId;

            // Resource Clears
            var neededClears = false;

            for (share.bufClears.constSlice()) |bufClear| {
                if (bufClear.passAfterClear == passId) {
                    try self.sortedRenderIR.append(.{ .clearBufIR = bufClear.rootResource });
                    neededClears = true;
                }
            }
            for (share.texClears.constSlice()) |texClear| {
                if (texClear.passAfterClear == passId) {
                    try self.sortedRenderIR.append(.{ .clearTexIR = texClear.rootResource });
                    neededClears = true;
                }
            }
            if (neededClears) try self.sortedRenderIR.append(.barrierBakeClears); // Call for Clear Barrier baking if needed

            // Passes
            self.sortedRenderIR.append(.{ .passIR = passId }) catch std.debug.print("7.PassSorter: Pass Append to sortedRenderNodes failed", .{});

            // Composites
            for (compositeData.composites.constSlice()) |composite| {
                if (composite.pass == passId) {
                    self.sortedRenderIR.append(.{ .compositeIR = composite }) catch std.debug.print("7.PassSorter: Composite Append to sortedRenderNodes failed", .{});
                }
            }
        }

        // Debug Prints
        if (rc.FRAME_GRAPH_DEBUG or rc.FRAME_GRAPH_SORT_DEBUG) {
            std.debug.print("9.PassSorter:\n", .{});
            for (self.sortedRenderIR.constSlice(), 0..) |renderNode, index| {
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
