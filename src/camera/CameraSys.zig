const std = @import("std");
const zm = @import("zmath");
const ac = @import("../.configs/appConfig.zig");

const EntityData = @import("../ecs/EntityData.zig").EntityData;
const comp = @import("../ecs/Components.zig");
const EngineData = @import("../EngineData.zig").EngineData;
const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;

const M_PI = 3.14159;
const TWO_PI = 2 * M_PI;

// This is the memory layout expected by the Vulkan Uniform Buffer
pub const CamData = struct {
    viewProj: [4][4]f32,
    camPosAndFov: [4]f32,
    camDirAndAspectRatio: [4]f32,
    frustumCorners: [8][4]f32,
    frustumPlanes: [6][4]f32,
};

pub const CameraSys = struct {
    pub fn update(ecs: *EntityData, dt: f64, data: *const EngineData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {

        // PROCESS STATE (Movement)
        var activeCamId: ?u32 = null;

        if (data.viewport.selectedViewportId) |viewId| {
            if (data.viewport.viewports.isKeyUsed(viewId.val)) {
                const viewport = data.viewport.viewports.getByKey(viewId.val);
                if (viewport.cameraEntity) |entityId| activeCamId = entityId.val;
            }
        }

        if (activeCamId != null and !data.window.uiActive) {
            const camId = activeCamId.?;

            // Check if this Entity actually has both required components
            if (ecs.transforms.isKeyUsed(camId) and ecs.cameras.isKeyUsed(camId)) {
                var transform = ecs.transforms.getPtrByKey(camId);
                var cam = ecs.cameras.getPtrByKey(camId);
                const input = &data.input;

                // Handle Rotation
                if (input.mouseMoveX != 0 or input.mouseMoveY != 0) {
                    transform.yaw -= input.mouseMoveX * ac.CAM_SENS;
                    transform.pitch -= input.mouseMoveY * ac.CAM_SENS;

                    transform.pitch = std.math.clamp(transform.pitch, -M_PI * 0.48, M_PI * 0.48);
                    if (transform.yaw > M_PI) transform.yaw -= TWO_PI;
                    if (transform.yaw < -M_PI) transform.yaw += TWO_PI;

                    transform.isDirty = true;
                }

                // Handle Movement
                const forward = getForward(transform.pitch, transform.yaw);
                const right = zm.normalize3(zm.cross3(forward, transform.up));
                const baseSpeed: f32 = if (input.speedMode) 3.0 else 1.0; // Speed increase Mode
                const speed = @as(f32, @floatCast(ac.CAM_SPEED * dt * baseSpeed));

                if (input.camForward) {
                    transform.pos += forward * zm.splat(zm.Vec, speed);
                    transform.isDirty = true;
                }
                if (input.camBackward) {
                    transform.pos -= forward * zm.splat(zm.Vec, speed);
                    transform.isDirty = true;
                }
                if (input.camLeft) {
                    transform.pos -= right * zm.splat(zm.Vec, speed);
                    transform.isDirty = true;
                }
                if (input.camRight) {
                    transform.pos += right * zm.splat(zm.Vec, speed);
                    transform.isDirty = true;
                }
                if (input.camUp) {
                    transform.pos += transform.up * zm.splat(zm.Vec, speed);
                    transform.isDirty = true;
                }
                if (input.camDown) {
                    transform.pos -= transform.up * zm.splat(zm.Vec, speed);
                    transform.isDirty = true;
                }

                // Handle FOV
                if (input.camFovInc) {
                    if (cam.fov < 140) cam.fov += @floatCast(ac.CAM_FOV_CHANGE * dt);
                    transform.isDirty = true;
                }
                if (input.camFovDec) {
                    if (cam.fov > 40) cam.fov -= @floatCast(ac.CAM_FOV_CHANGE * dt);
                    transform.isDirty = true;
                }
            }
        }

        // EXTRACT STATE TO RENDERER
        // Iterate linearly over all cameras
        for (data.viewport.viewports.getConstItems()) |viewport| {
            const camEntityId = viewport.cameraEntity orelse continue;

            if (!ecs.cameras.isKeyUsed(camEntityId.val)) continue;
            if (!ecs.transforms.isKeyUsed(camEntityId.val)) continue;

            var transform = ecs.transforms.getPtrByKey(camEntityId.val);
            const camComp = ecs.cameras.getPtrByKey(camEntityId.val);

            if (transform.isDirty) {
                // Calculate all GPU matrices based on raw component data
                const camData = calculateCameraData(transform.*, camComp.*);

                // Queue to renderer
                const arena = memoryMan.getGlobalArena();
                const camDataPtr = try arena.create(CamData);
                camDataPtr.* = camData;

                const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBuffer");
                const Payload = std.meta.Child(PayloadPtr);

                const updateBufferPtr = try arena.create(Payload);
                updateBufferPtr.* = .{ .bufId = camComp.bufId, .data = std.mem.asBytes(camDataPtr) };

                rendererQueue.append(.{ .updateBuffer = updateBufferPtr });

                // Reset dirty flag
                transform.isDirty = false;
            }
        }
    }

    // --- PURE MATH HELPERS ---

    inline fn getForward(pitch: f32, yaw: f32) zm.Vec {
        return zm.normalize3(zm.f32x4(
            @cos(pitch) * @sin(yaw),
            @sin(pitch),
            @cos(pitch) * @cos(yaw),
            0,
        ));
    }

    fn calculateCameraData(transform: comp.Transform, cam: comp.CameraComp) CamData {
        const forward = getForward(transform.pitch, transform.yaw);
        const right = zm.normalize3(zm.cross3(forward, transform.up));
        const camUp = zm.normalize3(zm.cross3(right, forward));

        // Matrices
        const target = transform.pos + forward;
        const view = zm.lookAtRh(transform.pos, target, transform.up);
        var proj = zm.perspectiveFovRh(cam.fov * (std.math.pi / 180.0), cam.aspectRatio, cam.near, cam.far);
        proj[1][1] *= -1.0;
        const viewProj = zm.mul(view, proj);

        // Frustum Corners
        const visFar: f32 = cam.far;
        const tanHalf = std.math.tan(cam.fov * (std.math.pi / 180.0) * 0.5);
        const nearH = cam.near * tanHalf;
        const nearW = nearH * cam.aspectRatio;
        const farH = visFar * tanHalf;
        const farW = farH * cam.aspectRatio;

        const nc = transform.pos + forward * zm.splat(zm.Vec, cam.near);
        const fc = transform.pos + forward * zm.splat(zm.Vec, visFar);

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
        for (pts, &corners) |p, *corn| corn.* = .{ p[0], p[1], p[2], 1.0 };

        return .{
            .viewProj = viewProj,
            .camPosAndFov = .{ transform.pos[0], transform.pos[1], transform.pos[2], cam.fov },
            .camDirAndAspectRatio = .{ forward[0], forward[1], forward[2], cam.aspectRatio },
            .frustumCorners = corners,
            .frustumPlanes = cornersToPlanes(corners),
        };
    }

    fn makePlane(p0: zm.Vec, p1: zm.Vec, p2: zm.Vec, centroid: zm.Vec) [4]f32 {
        var n = zm.normalize3(zm.cross3(p1 - p0, p2 - p0));
        if (zm.dot3(n, centroid - p0)[0] < 0) n = -n;
        return .{ n[0], n[1], n[2], -zm.dot3(n, p0)[0] };
    }

    fn cornersToPlanes(c: [8][4]f32) [6][4]f32 {
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

        var planes: [6][4]f32 = undefined;
        planes[0] = makePlane(v(c[0]), v(c[4]), v(c[2]), cent); // left
        planes[1] = makePlane(v(c[1]), v(c[3]), v(c[5]), cent); // right
        planes[2] = makePlane(v(c[0]), v(c[1]), v(c[4]), cent); // bottom
        planes[3] = makePlane(v(c[2]), v(c[6]), v(c[3]), cent); // top
        planes[4] = makePlane(v(c[0]), v(c[2]), v(c[1]), cent); // near
        planes[5] = makePlane(v(c[4]), v(c[5]), v(c[6]), cent); // far
        return planes;
    }
};
