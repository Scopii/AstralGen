const TextureDependancy = @import("../../frameBuild/components.zig").TextureDependancy;
const BufferDependancy = @import("../../frameBuild/components.zig").BufferDependancy;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 3

pub const DependancyData = struct {
    texDeps: FixedList(TextureDependancy, rc.PASS_MAX * rc.TEX_MAX) = .{},
    bufDeps: FixedList(BufferDependancy, rc.PASS_MAX * rc.BUF_MAX) = .{},

    lastBufWriter: SimpleIdMap(PassId, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    lastTexWriter: SimpleIdMap(PassId, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},
};
