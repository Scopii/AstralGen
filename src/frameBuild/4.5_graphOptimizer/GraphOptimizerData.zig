const BufLevelLifetime = @import("../../frameBuild/components.zig").BufLevelLifetime;
const TexLevelLifetime = @import("../../frameBuild/components.zig").TexLevelLifetime;
const GraphMemoryNode = @import("../../frameBuild/components.zig").GraphMemoryNode;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const PassEnum = @import("../../frameBuild/enums.zig").PassEnum;

// Step 4.5

pub const GraphOptimizerData = struct {
    bufLevelLifetimes: LinkedMap(BufLevelLifetime, 512, u16, 512, 0) = .{},
    texLevelLifetimes: LinkedMap(TexLevelLifetime, 512, u16, 512, 0) = .{},

    bufMemSize: LinkedMap(u64, 512, u16, 512, 0) = .{},
    texMemSize: LinkedMap(u64, 512, u16, 512, 0) = .{},

    graphMemNodes: FixedList(GraphMemoryNode, 512) = .{},
    optimizedGraph: LinkedMap(GraphMemoryNode, 512, u16, 512, 0) = .{},
};
