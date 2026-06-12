const TexGroupLifetime = @import("../../frameBuild/components.zig").TexGroupLifetime;
const BufGroupLifetime = @import("../../frameBuild/components.zig").BufGroupLifetime;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5.2

pub const LifetimeMergerData = struct {
    transientBufGroupLifetimes: FixedList(BufGroupLifetime, rc.BUF_MAX) = .{},
    transientTexGroupLifetimes: FixedList(TexGroupLifetime, rc.TEX_MAX) = .{},
};
