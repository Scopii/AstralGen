const GraphMemoryNode = @import("../../frameBuild/components.zig").GraphMemoryNode;
const GraphLifetime = @import("../../frameBuild/components.zig").GraphLifetime;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 4.5

pub const OptimizerData = struct {
    bufGraphLifetimes: LinkedIdMap(GraphLifetime, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texGraphLifetimes: LinkedIdMap(GraphLifetime, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    graphMemNodes: FixedList(GraphMemoryNode, rc.PASS_MAX) = .{},
    optimizedGraph: SimpleIdMap(GraphMemoryNode, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
};
