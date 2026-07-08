const RenderNode = @import("../render/types/pass/RenderNode.zig").RenderNode;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const rc = @import("../.configs/renderConfig.zig");

pub const RenderCompilerData = struct {
    sortedNodes: FixedList(RenderNode, rc.PASS_MAX + rc.MAX_WINDOWS * 4) = .{},
};
