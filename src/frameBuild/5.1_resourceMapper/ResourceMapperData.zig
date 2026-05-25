const TextureGroup = @import("../../frameBuild/components.zig").TextureGroup;
const TextureLink = @import("../../frameBuild/components.zig").TextureLink;
const BufferGroup = @import("../../frameBuild/components.zig").BufferGroup;
const BufferLink = @import("../../frameBuild/components.zig").BufferLink;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const TextureEnum = @import("../../frameBuild/enums.zig").TextureEnum;
const BufferEnum = @import("../../frameBuild/enums.zig").BufferEnum;

// Step 5.1

pub const ResourceMapperData = struct {
    // Last Frame Build Results
    lastBufGroupsTransient: BufGroupMap = .{},
    lastBufGroupsPersistent: BufGroupMap = .{},
    lastTexGroupsTransient: TexGroupMap = .{},
    lastTexGroupsPersistent: TexGroupMap = .{},

    // Temporary (For Buffers)
    bufferEnums: LinkedMap(BufferEnum, 512, u16, 512, 0) = .{},
    linkedBuffers: FixedList(BufferLink, 512) = .{},
    allSharedBuffers: LinkedMap(BufferEnum, 512, u16, 512, 0) = .{},

    // Buffer Results
    bufMapTransient: LinkedMap(BufferEnum, 512, u16, 512, 0) = .{},
    bufGroupsTransient: BufGroupMap = .{},

    bufMapPersistent: LinkedMap(BufferEnum, 512, u16, 512, 0) = .{},
    bufGroupsPersistent: BufGroupMap = .{},

    // Temporary (For Textures)
    textureEnums: LinkedMap(TextureEnum, 512, u16, 512, 0) = .{},
    linkedTextures: FixedList(TextureLink, 512) = .{},
    allSharedTextures: LinkedMap(TextureEnum, 512, u16, 512, 0) = .{},

    // Texture Results
    texMapTransient: LinkedMap(TextureEnum, 512, u16, 512, 0) = .{},
    texGroupsTransient: TexGroupMap = .{},

    texMapPersistent: LinkedMap(TextureEnum, 512, u16, 512, 0) = .{},
    texGroupsPersistent: TexGroupMap = .{},

    pub const BufGroupMap = LinkedMap(BufferGroup, 512, u16, 512, 0);
    pub const TexGroupMap = LinkedMap(TextureGroup, 512, u16, 512, 0);
};
