const RenderNode = @import("../../render/types/pass/RenderNode.zig").RenderNode;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 7

pub const SorterData = struct {
    sortedNodes: FixedList(RenderNode, rc.PASS_MAX + rc.MAX_WINDOWS * 4) = .{},
};
