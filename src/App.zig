// Imports
const std = @import("std");
const WindowManager = @import("platform/WindowManager.zig").WindowManager;
const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const Renderer = @import("vulkan/Renderer.zig").Renderer;
const EventManager = @import("core/EventManager.zig").EventManager;
const TimeManager = @import("core/TimeManager.zig").TimeManager;
const FileManager = @import("core/FileManager.zig").FileManager;
const Camera = @import("core/Camera.zig").Camera;
const zjobs = @import("zjobs");
const CreateMapArray = @import("structures/MapArray.zig").CreateMapArray;

pub const App = struct {
    memoryMan: *MemoryManager,
    windowMan: WindowManager,
    renderer: Renderer,
    timeMan: TimeManager,
    cam: Camera,
    eventMan: EventManager,
    fileMan: FileManager,

    pub fn init(memoryMan: *MemoryManager) !App {
        var windowMan = WindowManager.init() catch |err| {
            std.debug.print("WindowManager could not launch, Err {}\n", .{err});
            return error.WindowManagerFailed;
        };
        errdefer windowMan.deinit();

        var fileMan = FileManager.init(memoryMan.getAllocator()) catch |err| {
            windowMan.showErrorBox("File Manager could not launch", "\n");
            std.debug.print("Err {}\n", .{err});
            return error.FileManagerFailed;
        };
        errdefer fileMan.deinit();

        var renderer = Renderer.init(memoryMan) catch |err| {
            windowMan.showErrorBox("Renderer could not launch", "\n");
            std.debug.print("Err {}\n", .{err});
            return error.RendererManagerFailed;
        };
        errdefer renderer.deinit();

        return .{
            .cam = Camera.init(.{}),
            .timeMan = TimeManager.init(),
            .eventMan = EventManager{},
            .memoryMan = memoryMan,
            .windowMan = windowMan,
            .renderer = renderer,
            .fileMan = fileMan,
        };
    }

    pub fn initWindows(self: *App) !void {
        try self.windowMan.addWindow("Astral1", 1600, 900, .compute);
        //try self.windowMan.addWindow("Astral2", 16 * 70, 9 * 70, .graphics);
        //try self.windowMan.addWindow("Astral3", 350, 350, .mesh);
    }

    pub fn deinit(self: *App) void {
        self.renderer.deinit();
        self.fileMan.deinit();
        self.windowMan.deinit();
        self.memoryMan.deinit();
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
            // Process Inputs
            windowMan.pollEvents() catch |err| {
                std.log.err("Error in pollEvents(): {}", .{err});
                break;
            };
            if (windowMan.keyEvents.len > 0) eventMan.mapKeyEvents(windowMan.consumeKeyEvents());
            if (windowMan.mouseMovements.len > 0) eventMan.mapMouseMovements(windowMan.consumeMouseMovements());

            // Update Time
            timeMan.update();
            const dt = timeMan.getDeltaTime(.nano, f64);
            const runTime = timeMan.getRuntime(.seconds, f32);

            cam.rotate(self.eventMan.mouseMoveX, self.eventMan.mouseMoveY);

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
                }
            }
            eventMan.cleanupAppEvents();
            eventMan.resetMouseMovement();

            // Process Window Changes
            if (windowMan.changedWindows.len > 0) {
                try renderer.update(windowMan.changedWindows.slice());
                try windowMan.cleanupWindows();
            }

            // Handle Close or Idle
            if (windowMan.close == true) return;
            if (windowMan.openWindows == 0) continue;

            // Draw and reset Frame Arena
            renderer.draw(cam, runTime) catch |err| {
                std.log.err("Error in renderer.draw(): {}", .{err});
                break;
            };
            memoryMan.*.resetArena();
        }
    }
};
