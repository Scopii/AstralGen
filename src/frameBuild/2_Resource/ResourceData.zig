const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const TextureAccess = @import("../../frameBuild/components.zig").TextureAccess;
const BufferAccess = @import("../../frameBuild/components.zig").BufferAccess;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 2

pub const ResourceData = struct {
    bufDescs: LinkedIdMap(BufDesc, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texDescs: LinkedIdMap(TexDesc, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    bufMemSizes: LinkedIdMap(u64, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{}, // Only used for transient Buffers
    texMemSizeS: LinkedIdMap(u64, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{}, // Only used for transient Textures
};
