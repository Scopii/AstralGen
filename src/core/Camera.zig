const std = @import("std");
const zm = @import("zmath");
const config = @import("../config.zig");

const M_PI = 3.14159; //3.1415927
const TWO_PI = 2 * M_PI;

pub const Camera = struct {
    pos: zm.Vec = zm.f32x4(0, 0, -5, 0),
    fov: f32 = config.CAM_INIT_FOV,
    aspectRatio: f32 = 16.0 / 9.0,
    near: f32 = 0.1,
    far: f32 = 100.0,
    up: zm.Vec = zm.f32x4(0, 1, 0, 0),
    pitch: f32 = 0.0,
    yaw: f32 = 0.0,

    pub fn init(cam: Camera) Camera {
        return cam;
    }

    pub fn rotate(self: *Camera, x: f32, y: f32) void {
        self.yaw -= x * config.CAM_SENS; // Horizontal mouse movement affects yaw
        self.pitch -= y * config.CAM_SENS; // Vertical mouse movement affect pitch
        // Clamp pitch for gimbal lock
        self.pitch = std.math.clamp(self.pitch, -M_PI * 0.48, M_PI * 0.48);
        // Wrap yaw around 2π
        if (self.yaw > M_PI) self.yaw -= TWO_PI;
        if (self.yaw < -M_PI) self.yaw += TWO_PI;
    }

    pub fn getForward(self: *Camera) zm.Vec {
        // Spherical coordinates to Cartesian
        return zm.normalize3(zm.f32x4(@cos(self.pitch) * @sin(self.yaw), @sin(self.pitch), @cos(self.pitch) * @cos(self.yaw), 0));
    }

    pub fn moveRight(self: *Camera, dt: f64) void {
        const forward = self.getForward();
        const right = zm.normalize3(zm.cross3(forward, self.up));
        const speed = @as(f32, @floatCast(config.CAM_SPEED * dt));
        const movement = right * zm.splat(zm.Vec, speed);
        self.pos = self.pos + movement;
    }

    pub fn moveLeft(self: *Camera, dt: f64) void {
        const forward = self.getForward();
        const right = zm.normalize3(zm.cross3(forward, self.up));
        const speed = @as(f32, @floatCast(config.CAM_SPEED * dt));
        const movement = right * zm.splat(zm.Vec, -speed);
        self.pos = self.pos + movement;
    }

    pub fn moveUp(self: *Camera, dt: f64) void {
        const speed = @as(f32, @floatCast(config.CAM_SPEED * dt));
        const movement = self.up * zm.splat(zm.Vec, speed);
        self.pos = self.pos + movement;
    }

    pub fn moveDown(self: *Camera, dt: f64) void {
        const speed = @as(f32, @floatCast(config.CAM_SPEED * dt));
        const movement = self.up * zm.splat(zm.Vec, -speed);
        self.pos = self.pos + movement;
    }

    pub fn moveForward(self: *Camera, dt: f64) void {
        const forward = self.getForward();
        const speed = @as(f32, @floatCast(config.CAM_SPEED * dt));
        const movement = forward * zm.splat(zm.Vec, speed);
        self.pos = self.pos + movement;
    }

    pub fn moveBackward(self: *Camera, dt: f64) void {
        const forward = self.getForward();
        const speed = @as(f32, @floatCast(config.CAM_SPEED * dt));
        const movement = forward * zm.splat(zm.Vec, -speed);
        self.pos = self.pos + movement;
    }

    pub fn getProjection(self: *const Camera) zm.Mat {
        var proj = zm.perspectiveFovRh(self.fov * (std.math.pi / 180.0), self.aspectRatio, self.near, self.far);
        proj[1][1] *= -1.0;
        return proj;
    }

    // Add this helper function to simplify your Renderer code
    pub fn getViewProj(self: *Camera) zm.Mat {
        const view = self.getView();
        const proj = self.getProjection();
        return zm.mul(view, proj);
    }

    pub fn getView(self: *Camera) zm.Mat {
        const target = self.pos + self.getForward();
        return zm.lookAtRh(self.pos, target, self.up);
    }

    pub fn getPos(self: *const Camera) [3]f32 {
        return [4]f32{ self.pos[0], self.pos[1], self.pos[2] };
    }

    pub fn increaseFov(self: *Camera, dt: f64) void {
        if (self.fov < 140) self.fov += @floatCast(config.CAM_FOV_CHANGE * dt);
        std.debug.print("Increase Fov to {}\n", .{@as(u32, @intFromFloat(self.fov))});
    }

    pub fn decreaseFov(self: *Camera, dt: f64) void {
        if (self.fov > 40) self.fov -= @floatCast(config.CAM_FOV_CHANGE * dt);
        std.debug.print("Decreased Fov to {}\n", .{@as(u32, @intFromFloat(self.fov))});
    }

    pub fn getPosAndFov(self: *const Camera) [4]f32 {
        return [4]f32{ self.pos[0], self.pos[1], self.pos[2], self.fov };
    }

    pub fn debug(self: *Camera) void {
        std.debug.print("{}\n", .{self});
    }

    pub fn deinit() void {}
};
