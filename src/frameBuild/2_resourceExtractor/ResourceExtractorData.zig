const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const TextureAccess = @import("../../frameBuild/components.zig").TextureAccess;
const BufferAccess = @import("../../frameBuild/components.zig").BufferAccess;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const rc = @import("../../.configs/renderConfig.zig");

// Step 2

pub const ResourceExtractorData = struct {
    bufAccesses: FixedList(BufferAccess, rc.PASS_MAX * rc.BUF_MAX) = .{},
    texAccesses: FixedList(TextureAccess, rc.PASS_MAX * rc.TEX_MAX) = .{},

    bufDescriptions: SimpleMap(BufDesc, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    texDescriptions: SimpleMap(TexDesc, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},

    bufMemSize: LinkedMap(u64, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{}, // Only used for transient Buffers
    texMemSize: LinkedMap(u64, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{}, // Only used for transient Textures

    passAccessRanges: LinkedMap(PassAccessRange, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{},
};
