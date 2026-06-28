const TexInf = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexInf;
const BufInf = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufInf;
const RenderNode = @import("../render/types/pass/RenderNode.zig").RenderNode;
const LoadedShader = @import("../shader/LoadedShader.zig").LoadedShader;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const Window = @import("../window/Window.zig").Window;
const vk = @import("../.modules/vk.zig").c;
const std = @import("std");

pub const RendererQueue = struct {
    rendererEvents: FixedList(RendererEvent, 127) = .{},

    pub fn append(self: *RendererQueue, rendererEvent: RendererEvent) void {
        self.rendererEvents.append(rendererEvent) catch |err| std.debug.print("RendererQueue.appendEvent failed: {}\n", .{err});
    }

    pub fn get(self: *RendererQueue) []const RendererEvent {
        return self.rendererEvents.constSlice();
    }

    pub fn clear(self: *RendererQueue) void {
        self.rendererEvents.clear();
    }

    pub const RendererEvent = union(enum) {
        toggleGpuProfiling,

        addTexture: *const struct { texInf: TexInf, data: ?[]const u8 },
        addBuffer: *const struct { bufInf: BufInf, data: ?[]const u8 },
        updateBuffer: *const struct { bufId: BufId, data: []const u8 },
        updateBufferSegment: *const struct { bufId: BufId, data: []const u8, elementOffset: u32 },
        updateTexture: *const struct { texId: TexId, data: []const u8, newExtent: ?vk.VkExtent3D },
        removeTexture: TexId,
        removeBuffer: BufId,
        updateWindowState: *const Window,
        addRenderNode: *const RenderNode,

        addShader: *const LoadedShader,
    };
};
