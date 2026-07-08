const RenderNodeIR = @import("../../render/types/pass/RenderNode.zig").RenderNodeIR;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 7

pub const SorterData = struct {
    sortedRenderIR: FixedList(RenderNodeIR, rc.PASS_MAX + rc.MAX_WINDOWS * 4) = .{},
};
