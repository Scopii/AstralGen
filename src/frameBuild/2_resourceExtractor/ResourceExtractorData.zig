const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const TextureAccess = @import("../../frameBuild/components.zig").TextureAccess;
const BufferAccess = @import("../../frameBuild/components.zig").BufferAccess;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const rc = @import("../../.configs/renderConfig.zig");

// Step 2

pub const ResourceExtractorData = struct {
    bufAccesses: FixedList(BufferAccess, 512) = .{},
    texAccesses: FixedList(TextureAccess, 512) = .{},
    passAccessRanges: LinkedMap(PassAccessRange, 128, u16, 128, 0) = .{},
};
