const PassLifetime = @import("../../frameBuild/components.zig").PassLifetime;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const ResPassId = @import("../../.configs/idConfig.zig").ResPassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5

pub const LifetimeData = struct {
    passLifetimes: LinkedIdMap(PassLifetime, rc.RESOURCE_MAX, ResPassId, rc.RESOURCE_MAX, 0) = .{},
};
