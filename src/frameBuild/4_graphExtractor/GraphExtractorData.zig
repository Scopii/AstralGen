const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const GraphNode = @import("../../frameBuild/components.zig").GraphNode;
const PassEnum = @import("../../frameBuild/enums.zig").PassEnum;
const rc = @import("../../.configs/renderConfig.zig");

// Step 4

pub const GraphExtractorData = struct {
    passDepCounters: LinkedMap(u16, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{},
    unorderedPasses: LinkedMap(PassEnum, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{},
    readyPasses: FixedList(GraphNode, rc.PASS_MAX) = .{},

    // Result
    orderedPasses: LinkedMap(GraphNode, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{}, // Graph Node Does not Need Pass Since Pass Is Key
};
