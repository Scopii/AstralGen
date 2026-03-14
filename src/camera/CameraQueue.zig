const FixedList = @import("../.structures/FixedList.zig").FixedList;
const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const std = @import("std");
const CamId = @import("CameraSys.zig").CamId;
const Camera = @import("Camera.zig").Camera;

pub const CameraQueue = struct {
    cameraEvents: FixedList(CameraEvent, 127) = .{},

    pub fn append(self: *CameraQueue, camEvent: CameraEvent) void {
        self.cameraEvents.append(camEvent) catch |err| std.debug.print("InputQueue.appendEvent failed: {}\n", .{err});
    }

    pub fn get(self: *CameraQueue) []const CameraEvent {
        return self.cameraEvents.constSlice();
    }

    pub fn clear(self: *CameraQueue) void {
        self.cameraEvents.clear();
    }
};

pub const CameraEvent = union(enum) {
    camAdd: struct { camId: CamId, cam: Camera },
    camRemove: CamId,

    camForward,
    camBackward,
    camLeft,
    camRight,
    camUp,
    camDown,
    camFovInc,
    camFovDec,
    camRotate: struct { x: f32, y: f32 },
};
