const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const Access = @import("../../frameBuild/components.zig").Access;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 1.5

pub const AccessData = struct {
    accesses: FixedList(Access, rc.PASS_MAX * rc.RESOURCE_MAX) = .{},
    accessRanges: LinkedIdMap(PassAccessRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
};
