const FixedList = @import("../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../structures/LinkedMap.zig").LinkedMap;
const AppEvent = @import("../configs/appConfig.zig").AppEvent;
const ac = @import("../configs/appConfig.zig");
const std = @import("std");

pub const EngineQueue = @import("../state/EngineQueue.zig").EngineQueue;

pub const EngineSys = struct {
    pub fn clearAppEvents(eventState: *EngineQueue) void {
        eventState.appEvents.clear();
    }
};
