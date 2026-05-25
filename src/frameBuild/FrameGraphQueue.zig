const TexInf = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexInf;
const BufInf = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufInf;
const RenderNode = @import("../render/types/pass/PassDef.zig").RenderNode;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const vk = @import("../.modules/vk.zig").c;
const std = @import("std");

const pe = @import("enums.zig");
const TextureEnum = pe.TextureEnum;
const BufferEnum = pe.BufferEnum;
const PassEnum = pe.PassEnum;

pub const FrameGraphQueue = struct {
    frameGraphEvents: FixedList(FrameGraphEvent, 127) = .{},

    pub fn append(self: *FrameGraphQueue, rendererEvent: FrameGraphEvent) void {
        self.frameGraphEvents.append(rendererEvent) catch |err| std.debug.print("RendererQueue.appendEvent failed: {}\n", .{err});
    }

    pub fn get(self: *FrameGraphQueue) []const FrameGraphEvent {
        return self.frameGraphEvents.constSlice();
    }

    pub fn clear(self: *FrameGraphQueue) void {
        self.frameGraphEvents.clear();
    }

    pub const FrameGraphEvent = union(enum) {
        updateBuffer: *const GraphBufferUpdate,
        updateBufferSegment: *const GraphBufferUpdateSegment,
        updateTexture: *const GraphTextureUpdate,

        pub const GraphBufferUpdate = struct { bufEnum: BufferEnum, data: []const u8 };
        pub const GraphBufferUpdateSegment = struct { bufEnum: BufferEnum, data: []const u8, elementOffset: u32 };
        pub const GraphTextureUpdate = struct { texEnum: TextureEnum, data: []const u8, newExtent: ?vk.VkExtent3D };

        // addTexture: *const struct { texInf: TexInf, data: ?[]const u8 }, ??
        // addBuffer: *const struct { bufInf: BufInf, data: ?[]const u8 }, ??
        // addRenderNode: *const RenderNode, ??
    };
};
