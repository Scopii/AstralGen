const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const Camera = @import("../camera/Camera.zig").Camera;
const rc = @import("../.configs/renderConfig.zig");

pub const CameraData = struct {
    cameras: LinkedMap(Camera, rc.MAX_WINDOWS, u8, rc.MAX_WINDOWS, 0) = .{},
};
