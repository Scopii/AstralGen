const GroupLifetime = @import("../../frameBuild/components.zig").GroupLifetime;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const ResLink = @import("../../frameBuild/components.zig").ResLink;
const Group = @import("../../frameBuild/components.zig").Group;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5.1

pub const MapperData = struct {
    pub const GroupMap = LinkedMap(Group, rc.RESOURCE_MAX, u16, rc.RESOURCE_MAX, 0);
    // Last Frame Build Results
    prevTransientGroups: GroupMap = .{},
    prevPersistentGroups: GroupMap = .{},

    // Build Results
    persistentGroups: GroupMap = .{},
    transientGroups: GroupMap = .{},

    // Temporary
    resPassIds: LinkedMap(u16, rc.RESOURCE_MAX, u16, rc.RESOURCE_MAX, 0) = .{},
    sharedResources: SimpleMap(u16, rc.RESOURCE_MAX, u16, rc.RESOURCE_MAX, 0) = .{},
    linkedResources: FixedList(ResLink, rc.RESOURCE_MAX) = .{},

    // Results
    transientMap: LinkedMap(u16, rc.RESOURCE_MAX, u16, rc.RESOURCE_MAX, 0) = .{},
    persistentMap: LinkedMap(u16, rc.RESOURCE_MAX, u16, rc.RESOURCE_MAX, 0) = .{},

    transientGroupLifetimes: FixedList(GroupLifetime, rc.RESOURCE_MAX) = .{},
};
