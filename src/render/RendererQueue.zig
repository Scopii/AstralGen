const FixedList = @import("../.structures/FixedList.zig").FixedList;
const std = @import("std");
const BufId = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufId;
const TexInf = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexInf;
const BufInf = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufInf;
const Pass = @import("../render/types/base/Pass.zig").Pass;
const Window = @import("../window/Window.zig").Window;
const LoadedShader = @import("../shader/LoadedShader.zig").LoadedShader;

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
        toggleUi,

        addTexture: *const struct { texInf: TexInf, data: ?[]const u8 },
        addBuffer: *const struct { bufInf: BufInf, data: ?[]const u8 },
        updateBuffer: *const struct { bufId: BufId, data: []const u8 },
        updateWindowState: *const Window,
        addPass: *const Pass,

        addShader: *const LoadedShader,

        pub fn getTagType(self: *RendererEvent, name: []const u8) type {
            const PayloadPtr = @FieldType(self, name);
            return std.meta.Child(PayloadPtr);
        }
    };
};
