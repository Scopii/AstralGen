const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const Dependancy = @import("../../frameBuild/components.zig").Dependancy;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const ResPassId = @import("../../.configs/idConfig.zig").ResPassId;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 3

pub const DependancyData = struct {
    deps: FixedList(Dependancy, rc.PASS_MAX * rc.RESOURCE_MAX) = .{},
    lastWriter: SimpleIdMap(PassId, rc.RESOURCE_MAX, ResPassId, rc.RESOURCE_MAX, 0) = .{},
};
