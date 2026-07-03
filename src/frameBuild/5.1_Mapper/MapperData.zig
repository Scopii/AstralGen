const TextureGroup = @import("../../frameBuild/components.zig").TextureGroup;
const TextureLink = @import("../../frameBuild/components.zig").TextureLink;
const BufferGroup = @import("../../frameBuild/components.zig").BufferGroup;
const BufferLink = @import("../../frameBuild/components.zig").BufferLink;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5.1

pub const MapperData = struct {
    // Last Frame Build Results
    lastBufGroupsTransient: BufGroupMap = .{},
    lastBufGroupsPersistent: BufGroupMap = .{},
    lastTexGroupsTransient: TexGroupMap = .{},
    lastTexGroupsPersistent: TexGroupMap = .{},

    // Temporary (For Buffers)
    bufPassIds: LinkedIdMap(BufPassId, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    linkedBuffers: FixedList(BufferLink, rc.BUF_MAX) = .{},
    sharedBuffers: SimpleIdMap(BufPassId, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},

    // Buffer Results
    bufMapTransient: LinkedIdMap(BufPassId, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    bufGroupsTransient: BufGroupMap = .{},

    bufMapPersistent: LinkedIdMap(BufPassId, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    bufGroupsPersistent: BufGroupMap = .{},

    // Temporary (For Textures)
    texPassIds: LinkedIdMap(TexPassId, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},
    linkedTextures: FixedList(TextureLink, rc.TEX_MAX) = .{},
    sharedTextures: SimpleIdMap(TexPassId, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    // Texture Results
    texMapTransient: LinkedIdMap(TexPassId, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},
    texGroupsTransient: TexGroupMap = .{},

    texMapPersistent: LinkedIdMap(TexPassId, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},
    texGroupsPersistent: TexGroupMap = .{},

    pub const BufGroupMap = LinkedIdMap(BufferGroup, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0);
    pub const TexGroupMap = LinkedIdMap(TextureGroup, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0);
};
