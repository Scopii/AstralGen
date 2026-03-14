const BufId = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufId;
const ac = @import("../.configs/appConfig.zig");
const std = @import("std");
const zm = @import("zmath");

const M_PI = 3.14159; //3.1415927
const TWO_PI = 2 * M_PI;

pub const CamData = struct {
    viewProj: [4][4]f32,
    camPosAndFov: [4]f32,
    camDir: [4]f32,
    frustumCorners: [8][4]f32,
    frustumPlanes: [6][4]f32,
};

pub const Camera = struct {
    pos: zm.Vec = zm.f32x4(0, 0, -5, 0),
    fov: f32 = ac.CAM_INIT_FOV,
    aspectRatio: f32 = 16.0 / 9.0,
    near: f32 = 0.1,
    far: f32 = 1000.0,
    up: zm.Vec = zm.f32x4(0, 1, 0, 0),
    pitch: f32 = 0.0,
    yaw: f32 = 0.0,
    needsUpdate: bool = true,

    bufId: BufId,

    pub fn init(cam: Camera) Camera {
        return cam;
    }

    pub fn deinit() void {}

    fn computeFrustumCorners(self: *Camera) [8][4]f32 {
        const visFar: f32 = self.far; // cap so far corners stay within live camera range

        const forward = self.getForward();
        const right = zm.normalize3(zm.cross3(forward, self.up));
        const camUp = zm.normalize3(zm.cross3(right, forward));

        const tanHalf = std.math.tan(self.fov * (std.math.pi / 180.0) * 0.5);
        const nearH = self.near * tanHalf;
        const nearW = nearH * self.aspectRatio;
        const farH = visFar * tanHalf; // not self.far
        const farW = farH * self.aspectRatio;

        const nc = self.pos + forward * zm.splat(zm.Vec, self.near);
        const fc = self.pos + forward * zm.splat(zm.Vec, visFar); // not self.far

        const pts = [8]zm.Vec{
            nc - right * zm.splat(zm.Vec, nearW) - camUp * zm.splat(zm.Vec, nearH),
            nc + right * zm.splat(zm.Vec, nearW) - camUp * zm.splat(zm.Vec, nearH),
            nc - right * zm.splat(zm.Vec, nearW) + camUp * zm.splat(zm.Vec, nearH),
            nc + right * zm.splat(zm.Vec, nearW) + camUp * zm.splat(zm.Vec, nearH),
            fc - right * zm.splat(zm.Vec, farW) - camUp * zm.splat(zm.Vec, farH),
            fc + right * zm.splat(zm.Vec, farW) - camUp * zm.splat(zm.Vec, farH),
            fc - right * zm.splat(zm.Vec, farW) + camUp * zm.splat(zm.Vec, farH),
            fc + right * zm.splat(zm.Vec, farW) + camUp * zm.splat(zm.Vec, farH),
        };
        var corners: [8][4]f32 = undefined;
        for (pts, &corners) |p, *c| c.* = .{ p[0], p[1], p[2], 1.0 };
        return corners;
    }

    fn makePlane(p0: zm.Vec, p1: zm.Vec, p2: zm.Vec, centroid: zm.Vec) [4]f32 {
        var n = zm.normalize3(zm.cross3(p1 - p0, p2 - p0));
        if (zm.dot3(n, centroid - p0)[0] < 0) n = -n; // ensure inward-facing
        return .{ n[0], n[1], n[2], -zm.dot3(n, p0)[0] };
    }

    fn cornersToPlanes(c: [8][4]f32) [6][4]f32 {
        // centroid as inward reference
        var cx: f32 = 0;
        var cy: f32 = 0;
        var cz: f32 = 0;
        for (c) |p| {
            cx += p[0];
            cy += p[1];
            cz += p[2];
        }
        const cent = zm.f32x4(cx / 8, cy / 8, cz / 8, 0);

        const v = struct {
            fn get(p: [4]f32) zm.Vec {
                return zm.f32x4(p[0], p[1], p[2], 0);
            }
        }.get;

        // corner layout: 0-3 near (bl,br,tl,tr), 4-7 far (bl,br,tl,tr)
        var planes: [6][4]f32 = undefined;
        planes[0] = makePlane(v(c[0]), v(c[4]), v(c[2]), cent); // left
        planes[1] = makePlane(v(c[1]), v(c[3]), v(c[5]), cent); // right
        planes[2] = makePlane(v(c[0]), v(c[1]), v(c[4]), cent); // bottom
        planes[3] = makePlane(v(c[2]), v(c[6]), v(c[3]), cent); // top
        planes[4] = makePlane(v(c[0]), v(c[2]), v(c[1]), cent); // near
        planes[5] = makePlane(v(c[4]), v(c[5]), v(c[6]), cent); // far
        return planes;
    }

    pub fn toggleFreezeFrustum(self: *Camera) void {
        self.freezeFrustum = !self.freezeFrustum;
        self.needsUpdate = true;
    }

    pub fn rotate(self: *Camera, x: f32, y: f32) void {
        self.yaw -= x * ac.CAM_SENS; // Horizontal mouse movement affects yaw
        self.pitch -= y * ac.CAM_SENS; // Vertical mouse movement affect pitch
        // Clamp pitch for gimbal lock
        self.pitch = std.math.clamp(self.pitch, -M_PI * 0.48, M_PI * 0.48);
        // Wrap yaw around 2π
        if (self.yaw > M_PI) self.yaw -= TWO_PI;
        if (self.yaw < -M_PI) self.yaw += TWO_PI;

        self.needsUpdate = true;
    }

    pub fn getCameraData(self: *Camera) CamData {
        const vp = self.getViewProj();
        const liveCorners = self.computeFrustumCorners();

        return .{
            .viewProj = vp,
            .camPosAndFov = self.getPosAndFov(),
            .camDir = self.getForward(),
            .frustumCorners = liveCorners,
            .frustumPlanes = cornersToPlanes(liveCorners),
        };
    }

    fn getForward(self: *Camera) zm.Vec {
        // Spherical coordinates to Cartesian
        return zm.normalize3(zm.f32x4(@cos(self.pitch) * @sin(self.yaw), @sin(self.pitch), @cos(self.pitch) * @cos(self.yaw), 0));
    }

    pub fn moveRight(self: *Camera, dt: f64) void {
        const forward = self.getForward();
        const right = zm.normalize3(zm.cross3(forward, self.up));
        const speed = @as(f32, @floatCast(ac.CAM_SPEED * dt));
        const movement = right * zm.splat(zm.Vec, speed);
        self.pos = self.pos + movement;
        self.needsUpdate = true;
    }

    pub fn moveLeft(self: *Camera, dt: f64) void {
        const forward = self.getForward();
        const right = zm.normalize3(zm.cross3(forward, self.up));
        const speed = @as(f32, @floatCast(ac.CAM_SPEED * dt));
        const movement = right * zm.splat(zm.Vec, -speed);
        self.pos = self.pos + movement;
        self.needsUpdate = true;
    }

    pub fn moveUp(self: *Camera, dt: f64) void {
        const speed = @as(f32, @floatCast(ac.CAM_SPEED * dt));
        const movement = self.up * zm.splat(zm.Vec, speed);
        self.pos = self.pos + movement;
        self.needsUpdate = true;
    }

    pub fn moveDown(self: *Camera, dt: f64) void {
        const speed = @as(f32, @floatCast(ac.CAM_SPEED * dt));
        const movement = self.up * zm.splat(zm.Vec, -speed);
        self.pos = self.pos + movement;
        self.needsUpdate = true;
    }

    pub fn moveForward(self: *Camera, dt: f64) void {
        const forward = self.getForward();
        const speed = @as(f32, @floatCast(ac.CAM_SPEED * dt));
        const movement = forward * zm.splat(zm.Vec, speed);
        self.pos = self.pos + movement;
        self.needsUpdate = true;
    }

    pub fn moveBackward(self: *Camera, dt: f64) void {
        const forward = self.getForward();
        const speed = @as(f32, @floatCast(ac.CAM_SPEED * dt));
        const movement = forward * zm.splat(zm.Vec, -speed);
        self.pos = self.pos + movement;
        self.needsUpdate = true;
    }

    fn getProjection(self: *const Camera) zm.Mat {
        var proj = zm.perspectiveFovRh(self.fov * (std.math.pi / 180.0), self.aspectRatio, self.near, self.far);
        proj[1][1] *= -1.0;
        return proj;
    }

    fn getViewProj(self: *Camera) zm.Mat {
        const view = self.getView();
        const proj = self.getProjection();
        return zm.mul(view, proj);
    }

    fn getView(self: *Camera) zm.Mat {
        const target = self.pos + self.getForward();
        return zm.lookAtRh(self.pos, target, self.up);
    }

    fn getPos(self: *const Camera) [3]f32 {
        return [4]f32{ self.pos[0], self.pos[1], self.pos[2] };
    }

    pub fn increaseFov(self: *Camera, dt: f64) void {
        if (self.fov < 140) self.fov += @floatCast(ac.CAM_FOV_CHANGE * dt);
        std.debug.print("Increase Fov to {}\n", .{@as(u32, @intFromFloat(self.fov))});
        self.needsUpdate = true;
    }

    pub fn decreaseFov(self: *Camera, dt: f64) void {
        if (self.fov > 40) self.fov -= @floatCast(ac.CAM_FOV_CHANGE * dt);
        std.debug.print("Decreased Fov to {}\n", .{@as(u32, @intFromFloat(self.fov))});
        self.needsUpdate = true;
    }

    fn getPosAndFov(self: *const Camera) [4]f32 {
        return [4]f32{ self.pos[0], self.pos[1], self.pos[2], self.fov };
    }

    pub fn debug(self: *Camera) void {
        std.debug.print("{}\n", .{self});
    }
};
