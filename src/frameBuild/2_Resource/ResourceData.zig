const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const TextureAccess = @import("../../frameBuild/components.zig").TextureAccess;
const BufferAccess = @import("../../frameBuild/components.zig").BufferAccess;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 2

pub const ResourceData = struct {
    bufDescs: LinkedMap(BufDesc, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    texDescs: LinkedMap(TexDesc, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},

    bufMemSizes: LinkedMap(u64, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{}, // Only used for transient Buffers
    texMemSizeS: LinkedMap(u64, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{}, // Only used for transient Textures

};
