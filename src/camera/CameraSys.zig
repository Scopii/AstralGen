const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const Camera = @import("../camera/Camera.zig").Camera;

const CameraData = @import("../camera/CameraData.zig").CameraData;

pub const CamId = packed struct { val: u8 };

pub const CameraSys = struct {
    pub fn createCamera(cameraState: *CameraData, camId: CamId, cam: Camera) void {
        cameraState.cameras.upsert(camId.val, Camera.init(cam));
    }

    pub fn getCamera(cameraState: *CameraData, camId: CamId) !*Camera {
        return if (cameraState.cameras.isKeyUsed(camId.val)) cameraState.cameras.getPtrByKey(camId.val) else return error.CameraIdNotUsed;
    }

    pub fn removeCamera(cameraState: *CameraData, camId: CamId) void {
        cameraState.cameras.remove(camId.val);
    }
};
