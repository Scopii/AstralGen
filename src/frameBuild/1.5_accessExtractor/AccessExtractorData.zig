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

// Step 1.5

pub const AccessExtractorData = struct {
    bufAccesses: FixedList(BufferAccess, rc.PASS_MAX * rc.BUF_MAX) = .{},
    texAccesses: FixedList(TextureAccess, rc.PASS_MAX * rc.TEX_MAX) = .{},
    
    passAccessRanges: LinkedMap(PassAccessRange, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{},
};