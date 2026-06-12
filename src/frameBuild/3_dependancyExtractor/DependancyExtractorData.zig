const TextureDependancy = @import("../../frameBuild/components.zig").TextureDependancy;
const BufferDependancy = @import("../../frameBuild/components.zig").BufferDependancy;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const PassEnum = @import("../../frameBuild/enums.zig").PassEnum;
const rc = @import("../../.configs/renderConfig.zig");

// Step 3

pub const DependancyExtractorData = struct {
    texDependancies: FixedList(TextureDependancy, rc.PASS_MAX * rc.TEX_MAX) = .{}, // Correct Size?
    bufDependancies: FixedList(BufferDependancy, rc.PASS_MAX * rc.BUF_MAX) = .{}, // Correct Size?

    lastBufWriter: LinkedMap(PassEnum, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{}, // key: bufOutput Enum
    lastTexWriter: LinkedMap(PassEnum, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{}, // key: texOutput Enum
};
