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
const shaderCon = @import("configs/shaderConfig.zig");
const rc = @import("configs/renderConfig.zig");

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

        if (shaderCon.SHADER_STARTUP_COMPILATION) {
            try shaderCompiler.loadShaders(shaderCon.shadersToCompile);
        }

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
        try renderer.createGpuResource(rc.buffer1);
        try renderer.createGpuResource(rc.buffer2);

        try renderer.updateGpuBuffer(rc.buffer1.buffer, ecs.getObjects());

        try renderer.createGpuResource(rc.imgResource1);
        try renderer.createGpuResource(rc.imgResource2);
        try renderer.createGpuResource(rc.imgResource3);
        try renderer.createGpuResource(rc.imgResource4);
        try renderer.createGpuResource(rc.imgResource5);

        try renderer.addPasses(rc.renderSequence);

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
        try self.windowMan.addWindow("Task", 16 * 52, 9 * 52, rc.imgResource4.image.resourceId, 120, 50);
        try self.windowMan.addWindow("Mesh", 16 * 52, 9 * 52, rc.imgResource3.image.resourceId, 120, 550);
        try self.windowMan.addWindow("Compute", 16 * 52, 9 * 52, rc.imgResource1.image.resourceId, 960, 50);
        try self.windowMan.addWindow("Graphics", 16 * 52, 9 * 52, rc.imgResource2.image.resourceId, 960, 550);
    }

    pub fn run(self: *App) !void {
        const memoryMan = &self.memoryMan;
        const windowMan = &self.windowMan;
        const renderer = &self.renderer;
        const eventMan = &self.eventMan;
        const timeMan = &self.timeMan;
        const cam = &self.cam;

        // Main loop
        while (true) {
            // Poll Inputs
            windowMan.pollEvents() catch |err| {
                std.log.err("Error in pollEvents(): {}", .{err});
                break;
            };
            if (windowMan.inputEvents.len > 0) eventMan.mapKeyEvents(windowMan.consumeKeyEvents());
            if (windowMan.mouseMovements.len > 0) eventMan.mapMouseMovements(windowMan.consumeMouseMovements());

            // Process Window Changes
            if (windowMan.changedWindows.len > 0) {
                try renderer.updateWindowState(windowMan.getChangedWindows());
                windowMan.cleanupWindows();
            }

            // Close Or Idle
            if (windowMan.appExit == true) return;
            if (windowMan.openWindows == 0) continue;

            // Update Time
            timeMan.update();
            const dt = timeMan.getDeltaTime(.nano, f64);
            const runTime = timeMan.getRuntime(.seconds, f32);

            // Handle Mouse Input
            cam.rotate(self.eventMan.mouseMoveX, self.eventMan.mouseMoveY);
            eventMan.resetMouseChange();

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
                    .closeApp => return,
                    .restartApp => {},
                    .toggleFullscreen => windowMan.toggleMainFullscreen(),
                }
            }
            eventMan.clearAppEvents();

            // Shader Hotloading
            if (shaderCon.SHADER_HOTLOAD == true) {
                try self.shaderCompiler.checkShaderUpdates();
                try renderer.addShaders(self.shaderCompiler.pullFreshShaders());
                self.shaderCompiler.freeFreshShaders();
            }

            // Draw and reset Frame Arena
            renderer.draw(cam, runTime) catch |err| {
                std.log.err("Error in renderer.draw(): {}", .{err});
                break;
            };
            defer memoryMan.*.resetArena();

            windowMan.resetMainWindowOpacity();
        }
    }
};
