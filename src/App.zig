const TexId = @import("vulkan/types/res/TextureMeta.zig").TextureMeta.TexId;
const ShaderCompiler = @import("core/ShaderCompiler.zig").ShaderCompiler;
const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const RNGenerator = @import("core/RNGenerator.zig").RNGenerator;
const Renderer = @import("vulkan/sys/Renderer.zig").Renderer;
const shaderCon = @import("configs/shaderConfig.zig");
const Window = @import("types/Window.zig").Window;
const Camera = @import("types/Camera.zig").Camera;
const rc = @import("configs/renderConfig.zig");
const ac = @import("configs/appConfig.zig");
const zm = @import("zmath");
const std = @import("std");

const WindowState = @import("state/WindowState.zig").WindowState;
const WindowSys = @import("sys/WindowSys.zig").WindowSys;

const InputState = @import("state/InputState.zig").InputState;
const InputSys = @import("sys/InputSys.zig").InputSys;

const EventState = @import("state/EventState.zig").EventState;
const EventSys = @import("sys/EventSys.zig").EventSys;

const TimeState = @import("state/TimeState.zig").TimeState;
const TimeSys = @import("sys/TimeSys.zig").TimeSys;

const EntityState = @import("state/EntityState.zig").EntityState;
const EntitySys = @import("sys/EntitySys.zig").EntitySys;

const CameraState = @import("state/CameraState.zig").CameraState;
const CameraSys = @import("sys/CameraSys.zig").CameraSys;

pub const FrameData = struct {
    runTime: f32,
    deltaTime: f32,
};

pub const App = struct {
    windowState: WindowState,
    inputState: InputState,
    eventState: EventState,
    timeState: TimeState,
    entityState: EntityState,
    cameraState: CameraState,

    memoryMan: *MemoryManager,
    renderer: Renderer,
    shaderCompiler: ShaderCompiler,
    rng: RNGenerator,

    pub fn init(memoryMan: *MemoryManager) !App {
        var osState: WindowState = .{};
        const inputState: InputState = .{};
        const eventState: EventState = .{};
        const timeState: TimeState = .{};
        var entityState: EntityState = .{};
        const cameraState: CameraState = .{};

        WindowSys.init(&osState) catch |err| {
            std.debug.print("Astral App Error WindowManager could not launch, Err {}\n", .{err});
            return error.WindowManagerFailed;
        };
        errdefer WindowSys.deinit(&osState);

        var shaderCompiler = ShaderCompiler.init(memoryMan.getAllocator()) catch |err| {
            WindowSys.showErrorBox("Astral App Error", "File Manager could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.ShaderCompilerFailed;
        };
        errdefer shaderCompiler.deinit();

        try shaderCompiler.loadShaders(shaderCon.COMPILING_SHADERS);

        var rng = RNGenerator.init(std.Random.Xoshiro256, 1000);

        EntitySys.init(&entityState, &rng) catch |err| {
            WindowSys.showErrorBox("Astral App Error", "Entity Manager could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.EntityManagerFailed;
        };
        errdefer EntitySys.deinit(&entityState);

        var renderer = Renderer.init(memoryMan) catch |err| {
            WindowSys.showErrorBox("Astral App Error", "Renderer could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.RendererManagerFailed;
        };
        errdefer renderer.deinit();

        try renderer.addShaders(shaderCompiler.pullFreshShaders());
        shaderCompiler.freeFreshShaders();

        return .{
            .windowState = osState,
            .inputState = inputState,
            .eventState = eventState,
            .timeState = timeState,
            .entityState = entityState,
            .cameraState = cameraState,

            .memoryMan = memoryMan,
            .renderer = renderer,
            .shaderCompiler = shaderCompiler,
            .rng = rng,
        };
    }

    pub fn deinit(self: *App) void {
        self.renderer.deinit();
        self.shaderCompiler.deinit();
        WindowSys.deinit(&self.windowState);
        self.memoryMan.deinit();
    }

    pub fn setupApp(self: *App) !void {
        // CAMERA
        CameraSys.createCamera(&self.cameraState, .{ .val = 0 }, Camera.init(.{ .bufId = rc.cameraUB.id, .pos = zm.f32x4(0, 5, -20, 0), .yaw = 170, .near = 0.1, .far = 100, .fov = 60 }));
        CameraSys.createCamera(&self.cameraState, .{ .val = 1 }, Camera.init(.{ .bufId = rc.camera2UB.id, .pos = zm.f32x4(0, 20, -45, 0), .yaw = 170, .near = 0.1, .far = 300, .fov = 110 }));

        // RENDERING SET UP
        for (rc.BUFFERS) |bufInf| try self.renderer.addResource(bufInf, null);
        for (rc.TEXTURES) |texInf| try self.renderer.addResource(texInf, null);
        try self.renderer.createPasses(rc.PASSES);
        try self.renderer.updateBuffer(rc.objectSB.id, EntitySys.getObjects(&self.entityState));
    }

    pub fn initWindows(self: *App) !void {
        // try self.windowMan.addWindow("Task", 16 * 52, 9 * 52, rc.taskTex.id, 120, 50, true);
        // try self.windowMan.addWindow("Mesh", 16 * 52, 9 * 52, rc.meshTex.id, 120, 550, true);
        // try self.windowMan.addWindow("Compute", 16 * 52, 9 * 52, rc.compTex.id, 960, 50, true);
        // try self.windowMan.addWindow("Graphics", 16 * 52, 9 * 52, rc.grapTex.id, 960, 550, true);

        try WindowSys.addWindow(&self.windowState, "Debug", 1920 / 2, 1080 / 2, rc.quantDebugTex.id, 1920 / 2 - 10, 1080 / 2 - 10, true, &[_]TexId{rc.quantDebugDepthTex.id}, 1);
        try WindowSys.addWindow(&self.windowState, "Main", 1920 / 2, 1080 / 2, rc.quantTex.id, 10, 40, true, &[_]TexId{rc.quantDepthTex.id}, 0);
    }

    pub fn run(self: *App) !void {
        const osState = &self.windowState;
        const inputState = &self.inputState;
        const eventState = &self.eventState;
        const timeState = &self.timeState;
        const cameraState = &self.cameraState;

        const memoryMan = &self.memoryMan;
        const renderer = &self.renderer;

        var firstFrame = true;
        var frameData: FrameData = undefined;

        // Main loop
        while (true) {

            // Shader Hotloading
            if (shaderCon.SHADER_HOTLOAD == true) {
                try self.shaderCompiler.checkShaderUpdates();
                try renderer.addShaders(self.shaderCompiler.pullFreshShaders());
                self.shaderCompiler.freeFreshShaders();
            }

            if (rc.EARLY_GPU_WAIT == true) try renderer.waitForGpu();

            // Poll Inputs
            WindowSys.pollEvents(osState, inputState, &self.renderer.imguiMan) catch |err| {
                std.log.err("Error in pollEvents(): {}", .{err});
                break;
            };

            const activeCam = if (osState.mainWindow) |mainWindow| try CameraSys.getCamera(cameraState, mainWindow.camIndex) else null;

            // Handle Inputs
            if (inputState.inputEvents.len > 0) EventSys.mapKeyEvents(eventState, inputState);
            InputSys.clearKeyEvents(inputState);

            // Process Window Changes
            if (osState.changedWindows.len > 0) {
                try renderer.updateWindowStates(WindowSys.getChangedWindows(osState));
                WindowSys.cleanupWindows(osState);

                if (renderer.imguiMan.backendInitialized) {
                    osState.uiActive = renderer.imguiMan.uiActive; // sync
                }
            }

            // Close Or Idle
            if (osState.appExit == true) return;
            if (osState.openWindows == 0) continue;

            // Update Time
            TimeSys.update(timeState);
            frameData.runTime = TimeSys.getRuntime(timeState, .seconds, f32);
            frameData.deltaTime = TimeSys.getDeltaTime(timeState, .seconds, f32);
            const dt = TimeSys.getDeltaTime(timeState, .nano, f64);
            if (rc.CPU_PROFILING == true) std.debug.print("Cpu Delta {d:.3} ms, ({d:.1} Real FPS)\n", .{ dt * 0.000001, 1.0 / (dt * 0.000000001) });

            // Generate and Process and clear Events
            for (EventSys.getAppEvents(eventState)) |appEvent| {
                switch (appEvent) {
                    .closeApp => {
                        WindowSys.hideAllWindows(osState);
                        return;
                    },
                    .toggleFullscreen => WindowSys.toggleMainFullscreen(osState),

                    .toggleGpuProfiling => self.renderer.renderGraph.toggleGpuProfiling(),

                    .toggleFreezeFrustum => {
                        // if (activeCam) |cam| {
                        //     cam.toggleFreezeFrustum();
                        //     std.debug.print("Frustum Freeze: {}\n", .{cam.freezeFrustum});
                        // }
                    },

                    .toggleImgui => {
                        WindowSys.toogleUiMode(osState);
                        self.renderer.imguiMan.toogleUiMode();
                        osState.uiActive = self.renderer.imguiMan.uiActive;
                        std.debug.print("UI Toggle: {}\n", .{osState.uiActive});
                    },
                    else => {
                        if (osState.uiActive == false) {
                            if (activeCam) |cam| {
                                switch (appEvent) {
                                    .camForward => cam.moveForward(dt),
                                    .camBackward => cam.moveBackward(dt),
                                    .camUp => cam.moveUp(dt),
                                    .camDown => cam.moveDown(dt),
                                    .camLeft => cam.moveLeft(dt),
                                    .camRight => cam.moveRight(dt),
                                    .camFovIncrease => cam.increaseFov(dt),
                                    .camFovDecrease => cam.decreaseFov(dt),
                                    else => {},
                                }
                            }
                        }
                    },
                }
            }
            EventSys.clearAppEvents(eventState);

            if (osState.uiActive == false) {
                if (inputState.mouseMoveX != 0 or inputState.mouseMoveY != 0) {
                    if (activeCam) |cam| cam.rotate(inputState.mouseMoveX, inputState.mouseMoveY);
                    if (ac.MOUSE_MOVEMENT_INFO == true) std.debug.print("Mouse Total Movement x:{} y:{}\n", .{ inputState.mouseMoveX, inputState.mouseMoveY });
                    inputState.mouseMoveX = 0;
                    inputState.mouseMoveY = 0;
                }
            } else {
                inputState.mouseMoveX = 0;
                inputState.mouseMoveY = 0;
            }

            for (cameraState.cameras.getItems()) |*cam| {
                if (cam.needsUpdate) {
                    const camData = cam.getCameraData();
                    try renderer.updateBuffer(cam.bufId, &camData);
                    cam.needsUpdate = false;
                }
            }

            if (firstFrame) WindowSys.showAllWindows(osState);

            if (rc.EARLY_GPU_WAIT == false) try renderer.waitForGpu();
            // Draw and reset Frame Arena
            renderer.draw(frameData) catch |err| {
                std.log.err("Error in renderer.draw(): {}", .{err});
                break;
            };
            defer memoryMan.*.resetArena();

            if (rc.CPU_PROFILING or self.renderer.renderGraph.useGpuProfiling or rc.SWAPCHAIN_PROFILING) std.debug.print("\n", .{});

            // const endTime = std.time.nanoTimestamp();
            // const nsPerSecond = std.time.ns_per_s;
            // const frameLimit = 480;

            // const waitNs: u64 = nsPerSecond / frameLimit;

            // const frame_time = endTime - startTime;
            // if (frame_time < waitNs) {
            //     std.Thread.sleep(@intCast(waitNs - frame_time));
            // }

            if (firstFrame == false) continue;
            WindowSys.showOpacityAllWindows(osState);
            firstFrame = false;
        }
    }
};
