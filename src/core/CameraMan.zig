const LinkedMap = @import("../structures/LinkedMap.zig").LinkedMap;
const Camera = @import("Camera.zig").Camera;

pub const CamId = packed struct { val: u8 };

pub const CameraMan = struct {
    cameras: LinkedMap(Camera, 4, u8, 4, 0) = .{},

    pub fn createCamera(self: *CameraMan, camId: CamId, cam: Camera) void {
        self.cameras.upsert(camId.val, Camera.init(cam));
    }

    pub fn getCamera(self: *CameraMan, camId: CamId) !*Camera {
        return if (self.cameras.isKeyUsed(camId.val)) self.cameras.getPtrByKey(camId.val) else return error.CameraIdNotUsed;
    }
};