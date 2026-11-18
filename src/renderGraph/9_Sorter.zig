const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const RenderNodeIR = @import("../render/types/pass/RenderNode.zig").RenderNodeIR;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const CompositeData = @import("5.2_Composite.zig").CompositeData;
const OptimizerData = @import("6_Optimizer.zig").OptimizerData;
const ShareData = @import("8_Share.zig").ShareData;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const SorterData = struct {
    sortedRenderIR: FixedList(RenderNodeIR, rc.PASS_MAX + rc.MAX_WINDOWS * 4) = .{},
};

pub const SorterSys = struct {
    pub fn build(self: *SorterData, compositeData: *const CompositeData, optimizer: *const OptimizerData, share: *const ShareData, registry: *const RenderRegistryData, debug: bool) !void {
        self.sortedRenderIR.clear();

        try self.sortedRenderIR.append(.updateResourceStates);

        try self.sortedRenderIR.append(.syncPoint);

        try self.sortedRenderIR.append(.recordTransfers);

        const graphNodes = optimizer.optimizedGraph.getConstItems();

        for (graphNodes, 0..) |graphNode, index| {
            const curRange = optimizer.levelRanges.getByKey(@intCast(graphNode.level));
            const batchEnds = rc.FRAME_GRAPH_USE_GRAPH_LEVEL_LIFETIMES == false or curRange.last == index + 1;
            const batch = if (rc.FRAME_GRAPH_USE_GRAPH_LEVEL_LIFETIMES) graphNodes[curRange.first..curRange.last] else graphNodes[index .. index + 1];

            if (batchEnds) {
                try self.sortedRenderIR.append(.syncPoint);

                var hasClears = false;

                for (batch) |batchNode| {
                    if (share.bufClearIndices.isKeyUsed(batchNode.passId) == true) {
                        const bufClearRange = share.bufClearIndices.getByKey(batchNode.passId);

                        for (share.bufClears.constSlice()[bufClearRange.first..bufClearRange.last]) |bufClear| {
                            try self.sortedRenderIR.append(.{ .clearBufIR = bufClear.bufPassId });
                            hasClears = true;
                        }
                    }
                    if (share.texClearIndices.isKeyUsed(batchNode.passId) == true) {
                        const texClearRange = share.texClearIndices.getByKey(batchNode.passId);

                        for (share.texClearCmds.constSlice()[texClearRange.first..texClearRange.last]) |texClear| {
                            try self.sortedRenderIR.append(.{ .clearTexIR = texClear.texPassId });
                            hasClears = true;
                        }
                    }
                }

                if (hasClears) try self.sortedRenderIR.append(.syncPoint);

                // Passes
                for (batch) |batchNode| {
                    try self.sortedRenderIR.append(.{ .passIR = batchNode.passId });
                }

                // Composites

                for (batch) |batchNode| {
                    if (compositeData.compositeRanges.isKeyUsed(batchNode.passId) == true) {
                        const compRange = compositeData.compositeRanges.getByKey(batchNode.passId);

                        for (compositeData.sortedComposites.constSlice()[compRange.first..compRange.last]) |composite| {
                            try self.sortedRenderIR.append(.syncPoint); // Needs Sync points for correct overlaps
                            try self.sortedRenderIR.append(.{ .compositeIR = composite });
                        }
                    }
                }
            }
        }

        try self.sortedRenderIR.append(.syncPoint);

        try self.sortedRenderIR.append(.buildUi);

        try self.sortedRenderIR.append(.syncPoint);

        try self.sortedRenderIR.append(.present);

        try self.sortedRenderIR.append(.syncPoint);

        // Debug Prints
        if (debug or rc.FRAME_GRAPH_SORT_DEBUG) {
            std.debug.print("9.PassSorter:\n", .{});
            for (self.sortedRenderIR.constSlice(), 0..) |renderNode, index| {
                switch (renderNode) {
                    .syncPoint => std.debug.print("- {}. Sync Point\n", .{index}),
                    .passIR => |passId| std.debug.print("- {}. Pass: {s}\n", .{ index, try registry.getPassName(passId) }),
                    .clearBufIR => |bufPassId| std.debug.print("- {}. Pass Clears: {s}\n", .{ index, try registry.getBufferName(bufPassId) }),
                    .clearTexIR => |texPassId| std.debug.print("- {}. Pass Clears: {s}\n", .{ index, try registry.getTextureName(texPassId) }),
                    .compositeIR => |composite| std.debug.print("- {}. Composite: {s} (Pass {s})\n", .{ index, composite.name.get(), try registry.getPassName(composite.passId) }),
                    .present => std.debug.print("- {}. Present\n", .{index}),
                    .buildUi => std.debug.print("- {}. UiBuild\n", .{index}),
                    .updateResourceStates => std.debug.print("- {}. updateResourceStates\n", .{index}),
                    .recordTransfers => std.debug.print("- {}. recordTransfers\n", .{index}),
                }
            }
            std.debug.print("\n", .{});
        }
    }
};
