const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const Dependancy = @import("../../frameBuild/components.zig").Dependancy;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 3

pub const DependancyData = struct {
    deps: FixedList(Dependancy, rc.PASS_MAX * rc.RESOURCE_MAX) = .{},
    lastBufWriter: SimpleIdMap(PassId, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    lastTexWriter: SimpleIdMap(PassId, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},
};
