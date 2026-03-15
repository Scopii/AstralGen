
const Camera = @import("../camera/Camera.zig").Camera;
const CamData = @import("../camera/Camera.zig").CamData;
const std = @import("std");

const CameraData = @import("../camera/CameraData.zig").CameraData;
const WindowData = @import("../window/WindowData.zig").WindowData;
const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const CameraQueue = @import("../camera/CameraQueue.zig").CameraQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;

pub const CamId = packed struct { val: u8 };

pub const CameraSys = struct {
    pub fn update(cameraData: *CameraData, camQueue: *CameraQueue, dt: f64, windowData: *const WindowData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const camId = if (windowData.mainWindow) |window| window.camId else null;
        const idUsed = if (camId) |id| isCamIdUsed(cameraData, id) else false;
        const mainCam = if (idUsed and !windowData.uiActive) getCamera(cameraData, camId.?) else null; // Only update if Cam is used and UI is disabled

        for (camQueue.get()) |camEvent| {
            switch (camEvent) {
                .camForward => if (mainCam) |cam| cam.moveForward(dt),
                .camBackward => if (mainCam) |cam| cam.moveBackward(dt),
                .camUp => if (mainCam) |cam| cam.moveUp(dt),
                .camDown => if (mainCam) |cam| cam.moveDown(dt),
                .camLeft => if (mainCam) |cam| cam.moveLeft(dt),
                .camRight => if (mainCam) |cam| cam.moveRight(dt),
                .camFovInc => if (mainCam) |cam| cam.increaseFov(dt),
                .camFovDec => if (mainCam) |cam| cam.decreaseFov(dt),

                .camRotate => |rotation| if (mainCam) |cam| cam.rotate(rotation.x, rotation.y),

                .camAdd => |inf| addCamera(cameraData, inf.camId, inf.cam),
                .camRemove => |id| removeCamera(cameraData, id),
            }
        }
        camQueue.clear();

        for (cameraData.cameras.getItems()) |*cam| {
            if (cam.needsUpdate) {
                const arena = memoryMan.getGlobalArena();

                const camDataPtr = try arena.create(CamData);
                camDataPtr.* = cam.getCameraData();

                const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBuffer");
                const Payload = std.meta.Child(PayloadPtr);

                const updateBufferPtr = try arena.create(Payload);
                const byteSlice = std.mem.asBytes(camDataPtr);
                updateBufferPtr.* = .{ .bufId = cam.bufId, .data = byteSlice };

                rendererQueue.append(.{ .updateBuffer = updateBufferPtr });

                cam.needsUpdate = false;
            }
        }
    }

    fn addCamera(cameraData: *CameraData, camId: CamId, cam: Camera) void {
        cameraData.cameras.upsert(camId.val, Camera.init(cam));
    }

    fn isCamIdUsed(cameraData: *CameraData, camId: CamId) bool {
        return cameraData.cameras.isKeyUsed(camId.val);
    }

    fn getCamera(cameraData: *CameraData, camId: CamId) *Camera {
        return cameraData.cameras.getPtrByKey(camId.val);
    }

    fn removeCamera(cameraData: *CameraData, camId: CamId) void {
        cameraData.cameras.remove(camId.val);
    }
};
