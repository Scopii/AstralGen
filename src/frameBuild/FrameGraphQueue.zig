const TexInf = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexInf;
const BufInf = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufInf;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const vk = @import("../.modules/vk.zig").c;
const pe = @import("components.zig");
const std = @import("std");

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

        pub const GraphBufferUpdate = struct { bufPassId: BufPassId, data: []const u8 };
        pub const GraphBufferUpdateSegment = struct { bufPassId: BufPassId, data: []const u8, elementOffset: u32 };
        pub const GraphTextureUpdate = struct { texPassId: TexPassId, data: []const u8, newExtent: ?vk.VkExtent3D };

        // addTexture: *const struct { texInf: TexInf, data: ?[]const u8 }, ??
        // addBuffer: *const struct { bufInf: BufInf, data: ?[]const u8 }, ??
        // addRenderNode: *const RenderNode, ??
    };
};
