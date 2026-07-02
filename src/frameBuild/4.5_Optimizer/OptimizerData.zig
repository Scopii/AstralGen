const BufLevelLifetime = @import("../../frameBuild/components.zig").BufLevelLifetime;
const TexLevelLifetime = @import("../../frameBuild/components.zig").TexLevelLifetime;
const GraphMemoryNode = @import("../../frameBuild/components.zig").GraphMemoryNode;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 4.5

pub const OptimizerData = struct {
    bufLevelLifetimes: SimpleMap(BufLevelLifetime, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    texLevelLifetimes: SimpleMap(TexLevelLifetime, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},

    graphMemNodes: FixedList(GraphMemoryNode, rc.PASS_MAX) = .{},
    optimizedGraph: SimpleMap(GraphMemoryNode, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{},
};
