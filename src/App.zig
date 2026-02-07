const WindowManager = @import("platform/WindowManager.zig").WindowManager;
const ShaderCompiler = @import("core/ShaderCompiler.zig").ShaderCompiler;
const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const EntityManager = @import("ecs/EntityManager.zig").EntityManager;
const EventManager = @import("core/EventManager.zig").EventManager;
const TimeManager = @import("core/TimeManager.zig").TimeManager;
const RNGenerator = @import("core/RNGenerator.zig").RNGenerator;
const Renderer = @import("vulkan/sys/Renderer.zig").Renderer;
const shaderCon = @import("configs/shaderConfig.zig");
const Window = @import("platform/Window.zig").Window;
const Camera = @import("core/Camera.zig").Camera;
const rc = @import("configs/renderConfig.zig");
const ac = @import("configs/appConfig.zig");
const std = @import("std");

pub const App = struct {
    memoryMan: *MemoryManager,
    windowMan: WindowManager,
    renderer: Renderer,
    timeMan: TimeManager,
    cam: Camera,
    eventMan: EventManager,
    shaderCompiler: ShaderCompiler,
    ecs: EntityManager,
    rng: RNGenerator,

    pub fn init(memoryMan: *MemoryManager) !App {
        var windowMan = WindowManager.init() catch |err| {
            std.debug.print("Astral App Error WindowManager could not launch, Err {}\n", .{err});
            return error.WindowManagerFailed;
        };
        errdefer windowMan.deinit();

        try windowMan.addWindow("Main Rendering", 16 * 80, 9 * 80, rc.quantTex.id, 300, 200, true);

        var shaderCompiler = ShaderCompiler.init(memoryMan.getAllocator()) catch |err| {
            windowMan.showErrorBox("Astral App Error", "File Manager could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.ShaderCompilerFailed;
        };
        errdefer shaderCompiler.deinit();

        try shaderCompiler.loadShaders(shaderCon.COMPILING_SHADERS);

        var rng = RNGenerator.init(std.Random.Xoshiro256, 1000);

        var ecs = EntityManager.init(&rng) catch |err| {
            windowMan.showErrorBox("Astral App Error", "Entity Manager could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.EntityManagerFailed;
        };
        errdefer ecs.deinit();

        var renderer = Renderer.init(memoryMan, windowMan.mainWindow.?.handle) catch |err| {
            windowMan.showErrorBox("Astral App Error", "Renderer could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.RendererManagerFailed;
        };
        errdefer renderer.deinit();

        try renderer.addShaders(shaderCompiler.pullFreshShaders());
        shaderCompiler.freeFreshShaders();

        // RENDERING SET UP
        try renderer.createBuffers(rc.BUFFERS);
        try renderer.createTexture(rc.TEXTURES);
        try renderer.createPasses(rc.PASSES);
        try renderer.updateBuffer(rc.objectSB, ecs.getObjects());

        return .{
            .cam = Camera.init(.{}),
            .timeMan = TimeManager.init(),
            .eventMan = EventManager{},
            .memoryMan = memoryMan,
            .windowMan = windowMan,
            .renderer = renderer,
            .shaderCompiler = shaderCompiler,
            .ecs = ecs,
            .rng = rng,
        };
    }

    pub fn deinit(self: *App) void {
        self.renderer.deinit();
        self.shaderCompiler.deinit();
        self.windowMan.deinit();
        self.memoryMan.deinit();
    }

    pub fn initWindows(_: *App) !void {
        // try self.windowMan.addWindow("Task", 16 * 52, 9 * 52, rc.taskTex.id, 120, 50, true);
        // try self.windowMan.addWindow("Mesh", 16 * 52, 9 * 52, rc.meshTex.id, 120, 550, true);
        // try self.windowMan.addWindow("Compute", 16 * 52, 9 * 52, rc.compTex.id, 960, 50, true);
        // try self.windowMan.addWindow("Graphics", 16 * 52, 9 * 52, rc.grapTex.id, 960, 550, true);

        // try self.windowMan.addWindow("Main Rendering", 16 * 80, 9 * 80, rc.quantTex.id, 300, 200, true);
    }

    pub fn run(self: *App) !void {
        const memoryMan = &self.memoryMan;
        const windowMan = &self.windowMan;
        const renderer = &self.renderer;
        const eventMan = &self.eventMan;
        const timeMan = &self.timeMan;
        const cam = &self.cam;

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
            windowMan.pollEvents() catch |err| {
                std.log.err("Error in pollEvents(): {}", .{err});
                break;
            };

            // Handle Inputs
            if (windowMan.inputEvents.len > 0) eventMan.mapKeyEvents(windowMan.consumeKeyEvents());

            // Process Window Changes
            if (windowMan.changedWindows.len > 0) {
                try renderer.updateWindowStates(windowMan.getChangedWindows());
                windowMan.cleanupWindows();
            }

            // Close Or Idle
            if (windowMan.appExit == true) return;
            if (windowMan.openWindows == 0) continue;

            // Update Time
            timeMan.update();
            frameData.runTime = timeMan.getRuntime(.seconds, f32);
            frameData.deltaTime = timeMan.getDeltaTime(.seconds, f32);
            const dt = timeMan.getDeltaTime(.nano, f64);
            if (rc.CPU_PROFILING == true) std.debug.print("Cpu Delta {d:.3} ms, ({d:.1} Real FPS)\n", .{ dt * 0.000001, 1.0 / (dt * 0.000000001) });

            // Generate and Process and clear Events
            for (eventMan.getAppEvents()) |appEvent| {
                switch (appEvent) {
                    .closeApp => {
                        windowMan.hideAllWindows();
                        return;
                    },
                    .toggleFullscreen => windowMan.toggleMainFullscreen(),

                    .toggleImgui => {
                        self.windowMan.toogleUiMode();
                        self.renderer.imguiMan.toogleUiMode();
                        std.debug.print("UI Toggle: {}\n", .{self.windowMan.uiActive});
                    },
                    else => {
                        if (self.windowMan.uiActive == false) {
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
                    },
                }
            }
            eventMan.clearAppEvents();

            if (self.windowMan.uiActive == false) {
                if (windowMan.mouseMoveX != 0 or windowMan.mouseMoveY != 0) {
                    cam.rotate(windowMan.mouseMoveX, windowMan.mouseMoveY);
                    if (ac.MOUSE_MOVEMENT_INFO == true) std.debug.print("Mouse Total Movement x:{} y:{}\n", .{ windowMan.mouseMoveX, windowMan.mouseMoveY });
                    windowMan.mouseMoveX = 0;
                    windowMan.mouseMoveY = 0;
                }
            } else {
                windowMan.mouseMoveX = 0;
                windowMan.mouseMoveY = 0;
            }

            if (cam.needsUpdate == true) {
                const camData = cam.getCameraData();
                try renderer.updateBuffer(rc.cameraUB, &camData);
                cam.needsUpdate = false;
            }

            if (firstFrame) windowMan.showAllWindows();

            if (rc.EARLY_GPU_WAIT == false) try renderer.waitForGpu();
            // Draw and reset Frame Arena
            renderer.draw(frameData) catch |err| {
                std.log.err("Error in renderer.draw(): {}", .{err});
                break;
            };
            defer memoryMan.*.resetArena();

            if (rc.CPU_PROFILING or rc.GPU_PROFILING or rc.SWAPCHAIN_PROFILING) std.debug.print("\n", .{});

            if (firstFrame == false) continue;
            windowMan.showOpacityAllWindows();
            firstFrame = false;
        }
    }
};

pub const FrameData = struct {
    runTime: f32,
    deltaTime: f32,
};
