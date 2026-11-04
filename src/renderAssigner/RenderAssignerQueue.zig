const TexInf = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexInf;
const BufInf = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufInf;
// const TexUnion = @import("../render/types/pass/RenderNode.zig").TexUnion;
// const BufUnion = @import("../render/types/pass/RenderNode.zig").BufUnion;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const vk = @import("../.modules/vk.zig").c;
const std = @import("std");

pub const RenderAssignerQueue = struct {
    renderAssignerEvent: FixedList(RenderAssignerEvent, 127) = .{},

    pub fn append(self: *RenderAssignerQueue, rendererEvent: RenderAssignerEvent) void {
        self.renderAssignerEvent.append(rendererEvent) catch |err| std.debug.print("RendererQueue.appendEvent failed: {}\n", .{err});
    }

    pub fn get(self: *RenderAssignerQueue) []const RenderAssignerEvent {
        return self.renderAssignerEvent.constSlice();
    }

    pub fn clear(self: *RenderAssignerQueue) void {
        self.renderAssignerEvent.clear();
    }

    pub const RenderAssignerEvent = union(enum) {
        createManualBuffer: []const u8, // Should Be String
        deleteManualBuffer: []const u8, // Should Be String
        createManualTexture: []const u8, // Should Be String
        deleteManualTexture: []const u8, // Should Be String
        updateBuffer: *const PassBufferUpdate,
        updateBufferSegment: *const PassBufferUpdateSegment,
        updateTexture: *const PassTextureUpdate,

        pub const PassBufferUpdate = struct { bufName: []const u8, data: []const u8 };
        pub const PassBufferUpdateSegment = struct { bufName: []const u8, data: []const u8, elementOffset: u32 };
        pub const PassTextureUpdate = struct { texName: []const u8, data: []const u8, newExtent: ?vk.VkExtent3D };

        // addTexture: *const struct { texInf: TexInf, data: ?[]const u8 }, ??
        // addBuffer: *const struct { bufInf: BufInf, data: ?[]const u8 }, ??
        // addRenderNode: *const RenderNode, ??
    };
};
