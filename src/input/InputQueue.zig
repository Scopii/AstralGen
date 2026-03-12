pub const InputQueue = struct {};

pub const InputEvent = union(enum) {
    keyPress,
    keyRelease,
    mouseMove,
};
