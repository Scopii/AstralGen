const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const KeyPool = @import("../../.structures/KeyPool.zig").KeyPool;
const rc = @import("../../.configs/renderConfig.zig");
const sc = @import("../../.configs/shaderConfig.zig");

pub const ResourceRegistryData = struct {
    bufDescPool: KeyPool(u16, rc.BUF_MAX) = .{},
    bufDesc: LinkedMap(BufDesc, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},

    texDescPool: KeyPool(u16, rc.TEX_MAX) = .{},
    texDesc: LinkedMap(TexDesc, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},
};
