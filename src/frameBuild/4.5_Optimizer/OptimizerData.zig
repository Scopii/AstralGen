const GraphMemoryNode = @import("../../frameBuild/components.zig").GraphMemoryNode;
const GraphLifetime = @import("../../frameBuild/components.zig").GraphLifetime;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 4.5

pub const OptimizerData = struct {
    graphLifetimes: LinkedMap(GraphLifetime, rc.RESOURCE_MAX, u16, rc.RESOURCE_MAX, 0) = .{},
    graphMemNodes: FixedList(GraphMemoryNode, rc.PASS_MAX) = .{},
    optimizedGraph: SimpleIdMap(GraphMemoryNode, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{}, // Result
};
