const GroupLifetime = @import("../../renderGraph/components.zig").GroupLifetime;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const ResPassId = @import("../../.configs/idConfig.zig").ResPassId;
const ResLink = @import("../../renderGraph/components.zig").ResLink;
const Group = @import("../../renderGraph/components.zig").Group;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5.1

pub const MapperData = struct {
    pub const GroupMap = LinkedIdMap(Group, rc.RESOURCE_MAX, ResPassId, rc.RESOURCE_MAX, 0);
    // Last Frame Build Results
    prevTransientGroups: GroupMap = .{},
    prevPersistentGroups: GroupMap = .{},

    // Build Results
    persistentGroups: GroupMap = .{},
    transientGroups: GroupMap = .{},

    // Temporary
    resPassIds: LinkedIdMap(ResPassId, rc.RESOURCE_MAX, ResPassId, rc.RESOURCE_MAX, 0) = .{},
    sharedResources: SimpleIdMap(ResPassId, rc.RESOURCE_MAX, ResPassId, rc.RESOURCE_MAX, 0) = .{},
    linkedResources: FixedList(ResLink, rc.RESOURCE_MAX) = .{},

    // Results
    transientMap: LinkedIdMap(ResPassId, rc.RESOURCE_MAX, ResPassId, rc.RESOURCE_MAX, 0) = .{},
    persistentMap: LinkedIdMap(ResPassId, rc.RESOURCE_MAX, ResPassId, rc.RESOURCE_MAX, 0) = .{},

    transientGroupLifetimes: FixedList(GroupLifetime, rc.RESOURCE_MAX) = .{},
};
