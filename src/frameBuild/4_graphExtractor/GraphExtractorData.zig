const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const GraphNode = @import("../../frameBuild/components.zig").GraphNode;
const PassEnum = @import("../../frameBuild/enums.zig").PassEnum;

// Step 4

pub const GraphExtractorData = struct {
    passDepCounters: LinkedMap(u16, 512, u16, 512, 0) = .{},
    unorderedPasses: LinkedMap(PassEnum, 512, u16, 512, 0) = .{},
    readyPasses: FixedList(GraphNode, 512) = .{},

    // Result
    orderedPasses: LinkedMap(GraphNode, 512, u16, 512, 0) = .{}, // Graph Node Does not Need Pass Since Pass Is Key
};
