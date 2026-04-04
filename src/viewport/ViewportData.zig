const Viewport = @import("Viewport.zig").Viewport;
const ViewportId = @import("ViewportSys.zig").ViewportId;
const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const rc = @import("../.configs/renderConfig.zig");

pub const ViewportData = struct {
    viewports: LinkedMap(Viewport, rc.MAX_WINDOWS * 4, u32, rc.MAX_WINDOWS * 4, 0) = .{},
    activeViewportId: ?ViewportId = null,
};
