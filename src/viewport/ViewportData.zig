const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const ViewportId = @import("ViewportSys.zig").ViewportId;
const rc = @import("../.configs/renderConfig.zig");
const Viewport = @import("Viewport.zig").Viewport;

pub const ViewportData = struct {
    viewports: LinkedMap(Viewport, rc.MAX_WINDOWS * 4, u32, rc.MAX_WINDOWS * 4, 0) = .{},
    activeViewportIds: FixedList(ViewportId, rc.MAX_WINDOWS * 4) = .{},
    selectedViewportId: ?ViewportId = null,
};
