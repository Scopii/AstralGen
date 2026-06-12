const PhysicalBufLifetime = @import("../../frameBuild/components.zig").PhysicalBufLifetime;
const PhysicalTexLifetime = @import("../../frameBuild/components.zig").PhysicalTexLifetime;
const TextureClear = @import("../../frameBuild/components.zig").TextureClear;
const BufferClear = @import("../../frameBuild/components.zig").BufferClear;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5.4

pub const GroupMergerData = struct {
    sharedBufLifetimes: FixedList(PhysicalBufLifetime, rc.BUF_MAX) = .{},
    sharedTexLifetimes: FixedList(PhysicalTexLifetime, rc.TEX_MAX) = .{},

    bufShareIndexMap: LinkedMap(u16, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{}, // key: Group Enum, element: sharedBufLifetime Index
    texShareIndexMap: LinkedMap(u16, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{}, // key: Group Enum, element: sharedTexLifetime Index

    bufClears: FixedList(BufferClear, rc.BUF_MAX * rc.PASS_MAX) = .{},
    texClears: FixedList(TextureClear, rc.TEX_MAX * rc.PASS_MAX) = .{},
};
