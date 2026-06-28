const RenderNode = @import("../../render/types/pass/RenderNode.zig").RenderNode;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const PassId = @import("../../frameBuild/components.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 7

pub const PassSorterData = struct {
    sortedRenderNodes: FixedList(RenderNode, rc.PASS_MAX + rc.MAX_WINDOWS * 4) = .{},
};
