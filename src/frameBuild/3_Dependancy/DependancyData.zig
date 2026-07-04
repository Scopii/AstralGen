const Dependancy = @import("../../frameBuild/components.zig").Dependancy;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 3

pub const DependancyData = struct {
    deps: FixedList(Dependancy, rc.PASS_MAX * rc.RESOURCE_MAX) = .{},
    lastWriter: SimpleMap(PassId, rc.RESOURCE_MAX, u16, rc.RESOURCE_MAX, 0) = .{},
};
