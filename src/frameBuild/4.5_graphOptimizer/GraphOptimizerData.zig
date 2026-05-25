const BufLevelLifetime = @import("../../frameBuild/components.zig").BufLevelLifetime;
const TexLevelLifetime = @import("../../frameBuild/components.zig").TexLevelLifetime;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const GraphNode = @import("../../frameBuild/components.zig").GraphNode;
const PassEnum = @import("../../frameBuild/enums.zig").PassEnum;

// Step 4.5

pub const GraphOptimizerData = struct {
    bufLevelLifetimes: LinkedMap(BufLevelLifetime, 512, u16, 512, 0) = .{},
    texLevelLifetimes: LinkedMap(TexLevelLifetime, 512, u16, 512, 0) = .{},
};
