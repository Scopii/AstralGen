const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
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

    bufDescriptions: LinkedMap(BufDesc, 512, u16, 512, 0) = .{},
    texDescriptions: LinkedMap(TexDesc, 512, u16, 512, 0) = .{},

    bufMemSize: LinkedMap(u64, 512, u16, 512, 0) = .{}, // Only used for transient Buffers
    texMemSize: LinkedMap(u64, 512, u16, 512, 0) = .{}, // Only used for transient Textures

    passAccessRanges: LinkedMap(PassAccessRange, 128, u16, 128, 0) = .{},
};
