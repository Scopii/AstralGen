const TextureLifetime = @import("../../frameBuild/components.zig").TextureLifetime;
const BufferLifetime = @import("../../frameBuild/components.zig").BufferLifetime;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5

pub const LifetimeExtractorData = struct {
    bufLifetimes: LinkedMap(BufferLifetime, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    texLifetimes: LinkedMap(TextureLifetime, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},
};
