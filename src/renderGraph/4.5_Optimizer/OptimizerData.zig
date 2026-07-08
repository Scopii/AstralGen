const GraphMemoryNode = @import("../../renderGraph/components.zig").GraphMemoryNode;
const GraphLifetime = @import("../../renderGraph/components.zig").GraphLifetime;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const ResPassId = @import("../../.configs/idConfig.zig").ResPassId;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 4.5

pub const OptimizerData = struct {
    graphLifetimes: LinkedIdMap(GraphLifetime, rc.RESOURCE_MAX, ResPassId, rc.RESOURCE_MAX, 0) = .{},
    graphMemNodes: FixedList(GraphMemoryNode, rc.PASS_MAX) = .{},
    optimizedGraph: SimpleIdMap(GraphMemoryNode, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{}, // Result
};
