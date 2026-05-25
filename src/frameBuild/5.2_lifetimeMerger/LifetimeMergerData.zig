const TexGroupLifetime = @import("../../frameBuild/components.zig").TexGroupLifetime;
const BufGroupLifetime = @import("../../frameBuild/components.zig").BufGroupLifetime;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;

// Step 5.2

pub const LifetimeMergerData = struct {
    transientBufGroupLifetimes: FixedList(BufGroupLifetime, 512) = .{},
    transientTexGroupLifetimes: FixedList(TexGroupLifetime, 512) = .{},
};
