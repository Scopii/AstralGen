const UnionList = @import("../.structures/UnionList.zig").UnionList;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const TexInf = @import("../render/types/res/Texture.zig").TexInf;
const BufInf = @import("../render/types/res/Buffer.zig").BufInf;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const vk = @import("../.modules/vk.zig").c;
const std = @import("std");

pub const RenderAssignerQueue = UnionList(RenderAssignerEvent, 127);

pub const RenderAssignerEvent = union(enum) {
    createManualBuffer: []const u8, // Should Be String
    deleteManualBuffer: []const u8, // Should Be String
    createManualTexture: []const u8, // Should Be String
    deleteManualTexture: []const u8, // Should Be String
    updateBuffer: PassBufferUpdate,
    updateBufferSegment: PassBufferUpdateSegment,
    updateTexture: PassTextureUpdate,

    pub const PassBufferUpdate = struct { bufName: []const u8, data: []const u8 };
    pub const PassBufferUpdateSegment = struct { bufName: []const u8, data: []const u8, elementOffset: u32 };
    pub const PassTextureUpdate = struct { texName: []const u8, data: []const u8, newExtent: vk.VkExtent3D };
};
