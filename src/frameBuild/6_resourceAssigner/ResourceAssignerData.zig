const TransientTexture = @import("../../frameBuild/components.zig").TransientTexture;
const TransientBuffer = @import("../../frameBuild/components.zig").TransientBuffer;
const TextureMeta = @import("../../render/types/res/TextureMeta.zig").TextureMeta;
const UpdateRequestEnum = @import("../../frameBuild/enums.zig").UpdateRequestEnum;
const BufferMeta = @import("../../render/types/res/BufferMeta.zig").BufferMeta;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const KeyPool = @import("../../.structures/KeyPool.zig").KeyPool;
const TexId = @import("../../.configs/idConfig.zig").TexId;
const BufId = @import("../../.configs/idConfig.zig").BufId;
const rc = @import("../../.configs/renderConfig.zig");

const TexInf = TextureMeta.TexInf;
const BufInf = BufferMeta.BufInf;

// Step 6

pub const ResourceAssignerData = struct {
    // Key Pools
    bufIdPool: KeyPool(u16, rc.BUF_MAX) = .{},
    texIdPool: KeyPool(u16, rc.TEX_MAX) = .{},

    // Transient Storage
    unusedTransientBufs: FixedList(TransientBuffer, rc.BUF_MAX) = .{},
    usedTransientBufs: FixedList(TransientBuffer, rc.BUF_MAX) = .{},
    unusedTransientTexes: FixedList(TransientTexture, rc.TEX_MAX) = .{},
    usedTransientTexes: FixedList(TransientTexture, rc.TEX_MAX) = .{},

    // Persistent Storage
    rootBufPhysicalMap: LinkedMap(BufInf, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    rootTexPhysicalMap: LinkedMap(TexInf, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},

    // Manuel Storage
    manualBufs: LinkedMap(BufInf, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    manualTexes: LinkedMap(TexInf, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},

    // Collective Storage Assignments
    bufAssigns: BufferAssignments = .{},
    texAssigns: TextureAssignments = .{},

    // Update Requests after Resource Recreations
    updateRequests: LinkedMap(UpdateRequestEnum, 64, u16, 64, 0) = .{},

    pub const BufferAssignments = LinkedMap(BufId, rc.BUF_MAX, u16, rc.BUF_MAX, 0);
    pub const TextureAssignments = LinkedMap(TexId, rc.TEX_MAX, u16, rc.TEX_MAX, 0);
};
