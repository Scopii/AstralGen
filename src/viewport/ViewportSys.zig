const ViewportData = @import("ViewportData.zig").ViewportData;
const EngineData = @import("../EngineData.zig").EngineData;
const std = @import("std");

pub const ViewportId = packed struct { val: u8 };

pub const ViewportSys = struct {
    pub fn update(viewportData: *ViewportData, data: *const EngineData) void {
        if (data.window.mainWindow) |mainWindow| viewportData.selectedViewportId = mainWindow.viewIds[0] else viewportData.selectedViewportId = null; // ONLY TAKES FIRST!

        viewportData.activeViewportIds.clear();

        for (data.window.activeWindows.constSlice()) |window| {
            for (window.viewIds) |viewId| {
                if (viewId) |id| viewportData.activeViewportIds.append(id) catch std.debug.print("ERROR: Could not append ViewId in ViewportSys.update()", .{});
            }
        }
    }
};
