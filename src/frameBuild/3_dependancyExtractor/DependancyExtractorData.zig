const TextureDependancy = @import("../../frameBuild/components.zig").TextureDependancy;
const BufferDependancy = @import("../../frameBuild/components.zig").BufferDependancy;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 3

pub const DependancyExtractorData = struct {
    texDependancies: FixedList(TextureDependancy, 512) = .{},
    bufDependancies: FixedList(BufferDependancy, 512) = .{},
};
