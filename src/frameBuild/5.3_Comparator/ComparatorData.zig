const GroupChange = @import("../../frameBuild/components.zig").GroupChange;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 6

pub const ComparatorData = struct {
    persistentChanges: FixedList(GroupChange, rc.RESOURCE_MAX) = .{},
};
