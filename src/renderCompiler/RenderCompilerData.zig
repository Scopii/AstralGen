const RenderNode = @import("../render/types/pass/RenderNode.zig").RenderNode;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const rc = @import("../.configs/renderConfig.zig");

const uiEstimate = 1024;
const renderNodeCount = rc.PASS_MAX + rc.MAX_PASS_ATTRIBUTES + uiEstimate;

pub const RenderCompilerData = struct {
    sortedNodes: FixedList(RenderNode, renderNodeCount) = .{}, // rc.PASS_MAX + rc.MAX_WINDOWS * 4 // rc.PASS_MAX * rc.MAX_PASS_ATTRIBUTES
    pushData: FixedList(u8, rc.PASS_MAX * 128) = .{}, // Still too small ??
    usedQueries: u8 = 0,
};
