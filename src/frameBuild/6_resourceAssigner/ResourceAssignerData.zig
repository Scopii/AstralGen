const TransientTexture = @import("../../frameBuild/components.zig").TransientTexture;
const TransientBuffer = @import("../../frameBuild/components.zig").TransientBuffer;
const TextureMeta = @import("../../render/types/res/TextureMeta.zig").TextureMeta;
const UpdateRequestEnum = @import("../../frameBuild/enums.zig").UpdateRequestEnum;
const BufferMeta = @import("../../render/types/res/BufferMeta.zig").BufferMeta;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const KeyPool = @import("../../.structures/KeyPool.zig").KeyPool;
const rc = @import("../../.configs/renderConfig.zig");

const TexInf = TextureMeta.TexInf;
const BufInf = BufferMeta.BufInf;
const TexId = TextureMeta.TexId;
const BufId = BufferMeta.BufId;

// Step 6

pub const ResourceAssignerData = struct {
    // Key Pools
    bufIdPool: KeyPool(u16, 512) = .{},
    texIdPool: KeyPool(u16, 512) = .{},

    // Transient Storage
    unusedTransientBufs: FixedList(TransientBuffer, 512) = .{},
    usedTransientBufs: FixedList(TransientBuffer, 512) = .{},
    unusedTransientTexes: FixedList(TransientTexture, 512) = .{},
    usedTransientTexes: FixedList(TransientTexture, 512) = .{},

    // Persistent Storage
    rootBufPhysicalMap: LinkedMap(BufInf, 512, u16, 512, 0) = .{},
    rootTexPhysicalMap: LinkedMap(TexInf, 512, u16, 512, 0) = .{},

    // Manuel Storage
    manualBufs: LinkedMap(BufInf, 64, u16, 64, 0) = .{},
    manualTexes: LinkedMap(TexInf, 64, u16, 64, 0) = .{},

    // Collective Storage Assignments
    bufAssigns: BufferAssignments = .{},
    texAssigns: TextureAssignments = .{},

    // Update Requests after Resource Recreations
    updateRequests: LinkedMap(UpdateRequestEnum, 64, u16, 64, 0) = .{},

    pub const BufferIdMap = LinkedMap(BufId, 512, u16, 512, 0);
    pub const BufferAssignments = LinkedMap(BufId, rc.BUF_MAX, u16, rc.BUF_MAX, 0);
    pub const TextureAssignments = LinkedMap(TexId, rc.TEX_MAX, u16, rc.TEX_MAX, 0);
};
