const PhysicalResLifetime = @import("../../frameBuild/components.zig").PhysicalResLifetime;
const ResourceClear = @import("../../frameBuild/components.zig").ResourceClear;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5.4

pub const GroupData = struct {
    sharedResLifetimes: FixedList(PhysicalResLifetime, rc.RESOURCE_MAX) = .{},
    shareIndexMap: LinkedMap(u16, rc.RESOURCE_MAX, u16, rc.RESOURCE_MAX, 0) = .{}, // key: Group Root ID, element: sharedBufLifetime Index

    resourceClears: FixedList(ResourceClear, rc.RESOURCE_MAX * rc.PASS_MAX) = .{},
};
