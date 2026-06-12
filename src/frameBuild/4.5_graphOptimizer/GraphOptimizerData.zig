const BufLevelLifetime = @import("../../frameBuild/components.zig").BufLevelLifetime;
const TexLevelLifetime = @import("../../frameBuild/components.zig").TexLevelLifetime;
const GraphMemoryNode = @import("../../frameBuild/components.zig").GraphMemoryNode;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const PassEnum = @import("../../frameBuild/enums.zig").PassEnum;
const rc = @import("../../.configs/renderConfig.zig");

// Step 4.5

pub const GraphOptimizerData = struct {
    bufLevelLifetimes: LinkedMap(BufLevelLifetime, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    texLevelLifetimes: LinkedMap(TexLevelLifetime, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},

    graphMemNodes: FixedList(GraphMemoryNode, rc.PASS_MAX) = .{},
    optimizedGraph: LinkedMap(GraphMemoryNode, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{},
};
