const PhysicalBufLifetime = @import("../../frameBuild/components.zig").PhysicalBufLifetime;
const PhysicalTexLifetime = @import("../../frameBuild/components.zig").PhysicalTexLifetime;
const TextureClear = @import("../../frameBuild/components.zig").TextureClear;
const BufferClear = @import("../../frameBuild/components.zig").BufferClear;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5.4

pub const GroupData = struct {
    sharedBufLifetimes: FixedList(PhysicalBufLifetime, rc.BUF_MAX) = .{},
    sharedTexLifetimes: FixedList(PhysicalTexLifetime, rc.TEX_MAX) = .{},

    bufShareIndexMap: LinkedIdMap(u16, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{}, // key: Group Root ID, element: sharedBufLifetime Index
    texShareIndexMap: LinkedIdMap(u16, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{}, // key: Group Root ID , element: sharedTexLifetime Index

    bufClears: FixedList(BufferClear, rc.BUF_MAX * rc.PASS_MAX) = .{},
    texClears: FixedList(TextureClear, rc.TEX_MAX * rc.PASS_MAX) = .{},
};
