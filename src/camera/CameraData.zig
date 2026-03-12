const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const Camera = @import("../camera/Camera.zig").Camera;

pub const CameraData = struct {
    cameras: LinkedMap(Camera, 4, u8, 4, 0) = .{},
};
