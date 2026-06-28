const TextureLifetime = @import("../../frameBuild/components.zig").TextureLifetime;
const BufferLifetime = @import("../../frameBuild/components.zig").BufferLifetime;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5

pub const LifetimeExtractorData = struct {
    bufLifetimes: SimpleMap(BufferLifetime, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    texLifetimes: SimpleMap(TextureLifetime, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},
};
