const BufGroupChange = @import("../../frameBuild/components.zig").BufGroupChange;
const TexGroupChange = @import("../../frameBuild/components.zig").TexGroupChange;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;

// Step 6

pub const MappingComparatorData = struct {
    persistentBufChanges: FixedList(BufGroupChange, 512) = .{},
    persistentTexChanges: FixedList(TexGroupChange, 512) = .{},
};
