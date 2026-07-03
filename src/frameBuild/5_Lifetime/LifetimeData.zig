const PassLifetime = @import("../../frameBuild/components.zig").PassLifetime;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5

pub const LifetimeData = struct {
    bufLifetimes: LinkedIdMap(PassLifetime, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texLifetimes: LinkedIdMap(PassLifetime, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},
};
