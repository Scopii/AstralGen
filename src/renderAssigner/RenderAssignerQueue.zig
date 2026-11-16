const UnionList = @import("../.structures/UnionList.zig").UnionList;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const TexInf = @import("../render/types/res/Texture.zig").TexInf;
const BufInf = @import("../render/types/res/Buffer.zig").BufInf;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const String = @import("../globalHelper.zig").String;
const vk = @import("../.modules/vk.zig").c;
const std = @import("std");

pub const RenderAssignerQueue = UnionList(RenderAssignerEvent, 127);

pub const RenderAssignerEvent = union(enum) {
    createManualBuffer: String(30, "NO_CREATE_MAN_BUF"), 
    deleteManualBuffer: String(30, "NO_DELETE_MAN_BUF"), 
    createManualTexture: String(30, "NO_CREATE_MAN_TEX"),
    deleteManualTexture: String(30, "NO_DELETE_MAN_TEX"),
    updateBuffer: PassBufferUpdate,
    updateBufferSegment: PassBufferUpdateSegment,
    updateTexture: PassTextureUpdate,

    pub const PassBufferUpdate = struct { bufName: String(30, "NO_BUF_UPDATE_NAME"), data: []const u8 };
    pub const PassBufferUpdateSegment = struct { bufName: String(30, "NO_BUF_SEGMENT_UPDATE_NAME"), data: []const u8, elementOffset: u32 };
    pub const PassTextureUpdate = struct { texName: String(30, "NO_TEX_UPDATE_NAME"), data: []const u8, newExtent: vk.VkExtent3D };
};
