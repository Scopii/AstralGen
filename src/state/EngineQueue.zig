const FixedList = @import("../structures/FixedList.zig").FixedList;
const AppEvent = @import("../configs/appConfig.zig").AppEvent;

pub const EngineQueue = struct {
    appEvents: FixedList(AppEvent, 500) = .{},
};
