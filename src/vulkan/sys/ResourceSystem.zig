const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
const DescriptorMan = @import("DescriptorMan.zig").DescriptorMan;
const PushData = @import("../types/res/PushData.zig").PushData;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const vkT = @import("../help/Types.zig");
const Allocator = std.mem.Allocator;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

const BufferBase = @import("../types/res/BufferBase.zig").BufferBase;
const TextureBase = @import("../types/res/TextureBase.zig").TextureBase;

pub const Transfer = struct {
    srcOffset: u64,
    dstResId: Buffer.BufId,
    dstOffset: u64,
    size: u64,
};

pub const ResourceSystem = struct {
    
};
