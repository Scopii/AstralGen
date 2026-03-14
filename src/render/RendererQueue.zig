const FixedList = @import("../.structures/FixedList.zig").FixedList;
const std = @import("std");

const BufId = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufId;
const TexInf = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexInf;
const Pass = @import("../render/types/base/Pass.zig").Pass;
const CamData = @import("../camera/Camera.zig").CamData;

const Window = @import("../window/Window.zig").Window;

pub const RendererQueue = struct {
    rendererEvents: FixedList(RendererEvent, 127) = .{},

    pub fn append(self: *RendererQueue, rendererEvent: RendererEvent) void {
        self.rendererEvents.append(rendererEvent) catch |err| std.debug.print("InputQueue.appendEvent failed: {}\n", .{err});
    }

    pub fn get(self: *RendererQueue) []const RendererEvent {
        return self.rendererEvents.constSlice();
    }

    pub fn clear(self: *RendererQueue) void {
        self.rendererEvents.clear();
    }
};

pub const RendererEvent = union(enum) {
    addShader,
    addTexture: TexInf,
    addBuffer,
    updateBuffer,
    updateWindowState: Window,
    toggleGpuProfiling,
    toggleUi,
    createPass: Pass,

    updateCam: struct { bufId: BufId, camData: CamData }, // seems scuffed
};
