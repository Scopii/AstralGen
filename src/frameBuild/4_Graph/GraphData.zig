const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const GraphNode = @import("../../frameBuild/components.zig").GraphNode;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 4

pub const GraphData = struct {
    passDepCounters: LinkedIdMap(u16, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    readyPasses: FixedList(GraphNode, rc.PASS_MAX) = .{},
    graph: SimpleIdMap(GraphNode, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
};
