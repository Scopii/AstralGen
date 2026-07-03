const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const TextureAccess = @import("../../frameBuild/components.zig").TextureAccess;
const BufferAccess = @import("../../frameBuild/components.zig").BufferAccess;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 1.5

pub const AccessData = struct {
    bufAccesses: FixedList(BufferAccess, rc.PASS_MAX * rc.BUF_MAX) = .{},
    texAccesses: FixedList(TextureAccess, rc.PASS_MAX * rc.TEX_MAX) = .{},
    
    passAccessRanges: LinkedIdMap(PassAccessRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
};