const LinkedMap = @import("../structures/LinkedMap.zig").LinkedMap;
const Camera = @import("../types/Camera.zig").Camera;

pub const CameraState = struct {
    cameras: LinkedMap(Camera, 4, u8, 4, 0) = .{},
};