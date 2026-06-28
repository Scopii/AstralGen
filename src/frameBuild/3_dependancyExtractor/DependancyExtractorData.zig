const TextureDependancy = @import("../../frameBuild/components.zig").TextureDependancy;
const BufferDependancy = @import("../../frameBuild/components.zig").BufferDependancy;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 3

pub const DependancyExtractorData = struct {
    texDependancies: FixedList(TextureDependancy, rc.PASS_MAX * rc.TEX_MAX) = .{}, 
    bufDependancies: FixedList(BufferDependancy, rc.PASS_MAX * rc.BUF_MAX) = .{}, 

    lastBufWriter: SimpleMap(PassId, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{}, // key: bufOutput Enum
    lastTexWriter: SimpleMap(PassId, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{}, // key: texOutput Enum
};
