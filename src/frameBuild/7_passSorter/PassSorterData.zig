const RenderNode = @import("../../render/types/pass/PassDef.zig").RenderNode;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const PassId = @import("../../frameBuild/components.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 7

pub const PassSorterData = struct {
    tempPasses: FixedList(u16, rc.PASS_MAX) = .{},
    tempBlits: FixedList(u16, rc.PASS_MAX) = .{},
    tempComposites: FixedList(u16, rc.PASS_MAX) = .{},
    
    sortedRenderNodes: FixedList(RenderNode, rc.PASS_MAX) = .{},
};
