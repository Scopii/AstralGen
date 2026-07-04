const GroupLifetime = @import("../../frameBuild/components.zig").GroupLifetime;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5.2

pub const MergerData = struct {
    transientGroupLifetimes: FixedList(GroupLifetime, rc.RESOURCE_MAX) = .{},
};
