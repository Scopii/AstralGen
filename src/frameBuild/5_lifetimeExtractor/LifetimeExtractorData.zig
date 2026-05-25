const TextureLifetime = @import("../../frameBuild/components.zig").TextureLifetime;
const BufferLifetime = @import("../../frameBuild/components.zig").BufferLifetime;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;

// Step 5

pub const LifetimeExtractorData = struct {
    bufLifetimes: LinkedMap(BufferLifetime, 512, u16, 512, 0) = .{},
    texLifetimes: LinkedMap(TextureLifetime, 512, u16, 512, 0) = .{},
};
