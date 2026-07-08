const PhysicalResLifetime = @import("../../renderGraph/components.zig").PhysicalResLifetime;
const TextureClear = @import("../../renderGraph/components.zig").TextureClear;
const BufferClear = @import("../../renderGraph/components.zig").BufferClear;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5.4

pub const GroupData = struct {
    sharedBufLifetimes: FixedList(PhysicalResLifetime, rc.BUF_MAX) = .{},
    sharedTexLifetimes: FixedList(PhysicalResLifetime, rc.TEX_MAX) = .{},

    bufShareIndexMap: LinkedIdMap(u16, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texShareIndexMap: LinkedIdMap(u16, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    bufClears: FixedList(BufferClear, rc.BUF_MAX) = .{},
    texClears: FixedList(TextureClear, rc.TEX_MAX) = .{},
};
