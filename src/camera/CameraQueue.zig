pub const CameraQueue = struct {};

pub const CameraEvent = union(enum) {
    camForward,
    camBackward,
    camLeft,
    camRight,
    camUp,
    camDown,
    camFovInc,
    camFovDec,
    camRotate,
};
