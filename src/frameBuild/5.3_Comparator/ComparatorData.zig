const BufGroupChange = @import("../../frameBuild/components.zig").BufGroupChange;
const TexGroupChange = @import("../../frameBuild/components.zig").TexGroupChange;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 6

pub const ComparatorData = struct {
    persistentBufChanges: FixedList(BufGroupChange, rc.BUF_MAX) = .{},
    persistentTexChanges: FixedList(TexGroupChange, rc.TEX_MAX) = .{},
};
