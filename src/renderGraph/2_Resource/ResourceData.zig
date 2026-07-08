const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const ResPassId = @import("../../.configs/idConfig.zig").ResPassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 2

pub const ResourceData = struct {
    bufDescs: LinkedIdMap(BufDesc, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texDescs: LinkedIdMap(TexDesc, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    memSizes: LinkedIdMap(u64, rc.RESOURCE_MAX, ResPassId, rc.RESOURCE_MAX, 0) = .{}, // Only used for transient Resources
};
