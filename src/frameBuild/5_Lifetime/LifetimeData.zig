const PassLifetime = @import("../../frameBuild/components.zig").PassLifetime;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5

pub const LifetimeData = struct {
    passLifetimes: LinkedMap(PassLifetime, rc.RESOURCE_MAX, u16, rc.RESOURCE_MAX, 0) = .{},
};
