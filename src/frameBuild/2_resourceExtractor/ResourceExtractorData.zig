const TextureAccess = @import("../../frameBuild/components.zig").TextureAccess;
const BufferAccess = @import("../../frameBuild/components.zig").BufferAccess;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 2

pub const ResourceExtractorData = struct {
    bufAccesses: FixedList(BufferAccess, 512) = .{},
    texAccesses: FixedList(TextureAccess, 512) = .{},
};
