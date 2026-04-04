const Viewport = @import("Viewport.zig").Viewport;
const ViewportId = @import("ViewportSys.zig").ViewportId;
const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const rc = @import("../.configs/renderConfig.zig");

pub const ViewportData = struct {
    viewports: LinkedMap(Viewport, rc.MAX_WINDOWS * 4, u32, rc.MAX_WINDOWS * 4, 0) = .{},
    activeViewportIds: FixedList(ViewportId, rc.MAX_WINDOWS * 4) = .{},
    selectedViewportId: ?ViewportId = null,
};
