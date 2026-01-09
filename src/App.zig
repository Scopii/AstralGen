// Imports
const std = @import("std");
const WindowManager = @import("platform/WindowManager.zig").WindowManager;
const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const Renderer = @import("vulkan/Renderer.zig").Renderer;
const EventManager = @import("core/EventManager.zig").EventManager;
const TimeManager = @import("core/TimeManager.zig").TimeManager;
const ShaderCompiler = @import("core/ShaderCompiler.zig").ShaderCompiler;
const EntityManager = @import("ecs/EntityManager.zig").EntityManager;
const UiManager = @import("core/UiManager.zig").UiManager;
const RNGenerator = @import("core/RNGenerator.zig").RNGenerator;
const Camera = @import("core/Camera.zig").Camera;
const CameraData = @import("core/Camera.zig").CameraData;
const shaderCon = @import("configs/shaderConfig.zig");
const rc = @import("configs/renderConfig.zig");
const FixedList = @import("structures/FixedList.zig").FixedList;
const Window = @import("platform/Window.zig").Window;

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

        var shaderCompiler = ShaderCompiler.init(memoryMan.getAllocator()) catch |err| {
            windowMan.showErrorBox("Astral App Error", "File Manager could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.ShaderCompilerFailed;
        };
        errdefer shaderCompiler.deinit();

        try shaderCompiler.loadShaders(shaderCon.shadersToCompile);

        var rng = RNGenerator.init(std.Random.Xoshiro256, 1000);

        var ecs = EntityManager.init(&rng) catch |err| {
            windowMan.showErrorBox("Astral App Error", "Entity Manager could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.EntityManagerFailed;
        };
        errdefer ecs.deinit();

        var renderer = Renderer.init(memoryMan) catch |err| {
            windowMan.showErrorBox("Astral App Error", "Renderer could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.RendererManagerFailed;
        };
        errdefer renderer.deinit();

        try renderer.addShaders(shaderCompiler.pullFreshShaders());
        shaderCompiler.freeFreshShaders();

        // RENDERING SET UP
        try renderer.createBuffers(rc.buffers);
        try renderer.createTexture(rc.textures);
        try renderer.createPasses(rc.passes);
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

    pub fn initWindows(self: *App) !void {
        try self.windowMan.addWindow("Task", 16 * 52, 9 * 52, rc.taskTex.id, 120, 50, true);
        try self.windowMan.addWindow("Mesh", 16 * 52, 9 * 52, rc.meshTex.id, 120, 550, true);
        try self.windowMan.addWindow("Compute", 16 * 52, 9 * 52, rc.compTex.id, 960, 50, true);
        try self.windowMan.addWindow("Graphics", 16 * 52, 9 * 52, rc.grapTex.id, 960, 550, true);
    }

    pub fn run(self: *App) !void {
        const memoryMan = &self.memoryMan;
        const windowMan = &self.windowMan;
        const renderer = &self.renderer;
        const eventMan = &self.eventMan;
        const timeMan = &self.timeMan;
        const cam = &self.cam;

        var firstFrame = true;

        var rendererData: RendererData = undefined;

        // Main loop
        while (true) {
            // Shader Hotloading
            if (shaderCon.SHADER_HOTLOAD == true) {
                try self.shaderCompiler.checkShaderUpdates();
                try renderer.addShaders(self.shaderCompiler.pullFreshShaders());
                self.shaderCompiler.freeFreshShaders();
            }

            // Poll Inputs
            windowMan.pollEvents() catch |err| {
                std.log.err("Error in pollEvents(): {}", .{err});
                break;
            };
            if (windowMan.inputEvents.len > 0) eventMan.mapKeyEvents(windowMan.consumeKeyEvents());
            if (windowMan.mouseMoves.len > 0) eventMan.mapMouseMovements(windowMan.consumeMouseMovements());

            // Process Window Changes
            if (windowMan.changedWindows.len > 0) {
                try renderer.updateWindowStates(windowMan.getChangedWindows());
                windowMan.cleanupWindows();
            }

            // Handle Mouse Input
            if (eventMan.mouseMoved() == true) {
                cam.rotate(self.eventMan.mouseMoveX, self.eventMan.mouseMoveY);
                eventMan.resetMouseChange();
            }

            // Close Or Idle
            if (windowMan.appExit == true) return;
            if (windowMan.openWindows == 0) continue;

            // Update Time
            timeMan.update();
            const dt = timeMan.getDeltaTime(.nano, f64);

            // Generate and Process and clear Events
            for (eventMan.getAppEvents()) |appEvent| {
                switch (appEvent) {
                    .camForward => cam.moveForward(dt),
                    .camBackward => cam.moveBackward(dt),
                    .camUp => cam.moveUp(dt),
                    .camDown => cam.moveDown(dt),
                    .camLeft => cam.moveLeft(dt),
                    .camRight => cam.moveRight(dt),
                    .camFovIncrease => cam.increaseFov(dt),
                    .camFovDecrease => cam.decreaseFov(dt),
                    .closeApp => {
                        windowMan.hideAllWindows();
                        return;
                    },
                    .restartApp => {},
                    .toggleFullscreen => windowMan.toggleMainFullscreen(),
                }
            }
            eventMan.clearAppEvents();

            if (firstFrame) windowMan.showAllWindows();

            rendererData.runTime = timeMan.getRuntime(.seconds, f32);
            rendererData.deltaTime = timeMan.getDeltaTime(.seconds, f32);

            if (cam.needsUpdate == true) {
                const camData = cam.getCameraData();
                try renderer.updateBuffer(rc.cameraUB, &camData);
                cam.needsUpdate = false;
            }

            // Draw and reset Frame Arena
            renderer.draw(rendererData) catch |err| {
                std.log.err("Error in renderer.draw(): {}", .{err});
                break;
            };
            defer memoryMan.*.resetArena();

            if (firstFrame) {
                windowMan.showOpacityAllWindows();
                firstFrame = false;
            }
        }
    }
};

pub const RendererData = struct {
    runTime: f32,
    deltaTime: f32,
};
