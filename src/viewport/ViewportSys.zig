const ViewportData = @import("ViewportData.zig").ViewportData;
const EngineData = @import("../EngineData.zig").EngineData;

pub const ViewportId = packed struct { val: u8 };

pub const ViewportSys = struct {
    pub fn update(viewportData: *ViewportData, data: *const EngineData) void {
        if (data.window.mainWindow) |mainWindow| viewportData.activeViewportId = mainWindow.viewIds[0] else viewportData.activeViewportId = null; // ONLY TAKES FIRST!
    }
};
