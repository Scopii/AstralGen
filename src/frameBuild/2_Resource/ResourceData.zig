const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 2

const MapType = if (rc.FRAME_GRAPH_DEBUG) LinkedIdMap else SimpleIdMap;

pub const ResourceData = struct {
    bufDescs: LinkedIdMap(BufDesc, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texDescs: LinkedIdMap(TexDesc, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    memSizes: LinkedMap(u64, rc.RESOURCE_MAX, u16, rc.RESOURCE_MAX, 0) = .{}, // Only used for transient Resources
};
