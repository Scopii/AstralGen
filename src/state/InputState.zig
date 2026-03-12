const FixedList = @import("../structures/FixedList.zig").FixedList;
const KeyEvent = @import("../sys/EventSys.zig").KeyEvent;

pub const InputState = struct {
    inputEvents: FixedList(KeyEvent, 127) = .{},
    mouseMoveX: f32 = 0,
    mouseMoveY: f32 = 0,
};
