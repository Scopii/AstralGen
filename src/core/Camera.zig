const zm = @import("zmath");
const std = @import("std");
const M_PI = 3.14159; //3.1415927
const TWO_PI = 2 * M_PI;

pub const Camera = struct {
    pos: zm.Vec = zm.f32x4(0, 0, 5, 0),
    fov: f32 = 90.0,
    aspectRatio: f32 = 16.0 / 9.0,
    near: f32 = 0.1,
    far: f32 = 100.0,
    radius: f32 = 5.0,
    up: zm.Vec = zm.f32x4(0, 1, 0, 0),
    azimuth: f32 = M_PI / 2.0, // Horizontal angle in radians
    elevation: f32 = 0, // Vertical angle in radians
    target: zm.Vec = zm.f32x4(0, 0, 0, 1.0), // The point to orbit

    // You can create a simple init function if needed
    pub fn init(cam: Camera) Camera {
        var newCam = cam;
        newCam.updatePosition();
        return newCam;
    }

    pub fn getView(self: *const Camera) zm.Mat {
        return zm.lookAtRh(self.pos, self.target, self.up);
    }

    pub fn getProjection(self: *const Camera) zm.Mat {
        // Standard OpenGL projection matrix (RH)
        return zm.perspectiveFovRh(self.fov * (M_PI / 180.0), // Convert FOV from degrees to radians
            self.aspectRatio, self.near, self.far);
    }

    pub fn getPos(self: *const Camera) [4]f32 {
        return [4]f32{ self.pos[0], self.pos[1], self.pos[2], 0 };
    }

    pub fn getRadius(self: *Camera) f32 {
        return self.radius;
    }

    pub fn moveLeft(self: *Camera) void {
        self.pos[0] -= 0.1;
    }

    pub fn moveRight(self: *Camera) void {
        self.pos[0] += 0.1;
    }

    pub fn moveUp(self: *Camera) void {
        self.pos[1] += 0.1;
    }

    pub fn moveDown(self: *Camera) void {
        self.pos[1] -= 0.1;
    }

    pub fn moveForward(self: *Camera) void {
        self.pos[2] += 0.1;
    }

    pub fn moveBackward(self: *Camera) void {
        self.pos[2] -= 0.1;
    }

    pub fn setRadius(it: *Camera, newRadius: f32) void {
        it.radius = newRadius;
    }

    pub fn updatePosition(self: *Camera) void {
        // First calculate the offset vector
        const x = self.radius * @cos(self.elevation) * @cos(self.azimuth);
        const y = self.radius * @sin(self.elevation);
        const z = self.radius * @cos(self.elevation) * @sin(self.azimuth);

        // Add offset to target (this is consistent with your C++ implementation)
        self.pos = zm.f32x4(self.target[0] + x, self.target[1] + y, self.target[2] + z, 0);
    }

    pub fn rotateHorizontal(self: *Camera, angleDegrees: f32) void {
        const angleRadians = angleDegrees * (M_PI / 180.0);
        self.azimuth += angleRadians;

        // Keep azimuth in the range [0, 2π]
        while (self.azimuth > TWO_PI) {
            self.azimuth -= TWO_PI;
        }
        while (self.azimuth < 0) {
            self.azimuth += TWO_PI;
        }

        self.updatePosition();
    }

    pub fn setHorizontal(self: *Camera, angleDegrees: f32) void {
        const angleRadians = angleDegrees * (M_PI / 180.0);
        self.azimuth = angleRadians;

        // Keep azimuth in the range [0, 2π]
        while (self.azimuth > TWO_PI) {
            self.azimuth -= TWO_PI;
        }
        while (self.azimuth < 0) {
            self.azimuth += TWO_PI;
        }

        self.updatePosition();
    }

    pub fn addHorizontal(self: *Camera, value: f32) void {
        self.azimuth += value;
        // Keep azimuth in the range [0, 2π]
        while (self.azimuth > TWO_PI) {
            self.azimuth -= TWO_PI;
        }
        while (self.azimuth < 0) {
            self.azimuth += TWO_PI;
        }
        self.updatePosition();
    }

    pub fn rotateVertical(self: *Camera, angleDegrees: f32) void {
        const angle_radians = angleDegrees * (M_PI / 180.0);
        self.elevation += angle_radians;
        self.elevation = @max(-M_PI / 2.0 + 0.1, @min(self.elevation, M_PI / 2.0 - 0.1));
        self.updatePosition();
    }

    pub fn addVertical(self: *Camera, value: f32) void {
        self.elevation += value;
        self.elevation = @max(-M_PI / 2.0 + 0.1, @min(self.elevation, M_PI / 2.0 - 0.1));
        self.updatePosition();
    }

    pub fn debug(self: *Camera) void {
        std.debug.print("{}\n", .{self});
    }

    pub fn deinit() void {}
};
