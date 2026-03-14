const TexId = @import("render/types/res/TextureMeta.zig").TextureMeta.TexId;
const ShaderCompiler = @import("core/ShaderCompiler.zig").ShaderCompiler;
const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const RNGenerator = @import("core/RNGenerator.zig").RNGenerator;
const shaderCon = @import(".configs/shaderConfig.zig");
const Window = @import("window/Window.zig").Window;
const Camera = @import("camera/Camera.zig").Camera;
const rc = @import(".configs/renderConfig.zig");
const ac = @import(".configs/appConfig.zig");
const zm = @import("zmath");
const std = @import("std");

const TimeState = @import("time/TimeState.zig").TimeState;
const TimeSys = @import("time/TimeSys.zig").TimeSys;

/// Systems
const WindowQueue = @import("window/WindowQueue.zig").WindowQueue;
const WindowState = @import("window/WindowState.zig").WindowData;
const WindowSys = @import("window/WindowSys.zig").WindowSys;

const InputQueue = @import("input/InputQueue.zig").InputQueue;
const InputData = @import("input/InputData.zig").InputData;
const InputSys = @import("input/InputSys.zig").InputSys;

const EntityQueue = @import("entity/EntityQueue.zig").EntityQueue;
const EntityData = @import("entity/EntityData.zig").EntityData;
const EntitySys = @import("entity/EntitySys.zig").EntitySys;

const CameraQueue = @import("camera/CameraQueue.zig").CameraQueue;
const CameraData = @import("camera/CameraData.zig").CameraData;
const CameraSys = @import("camera/CameraSys.zig").CameraSys;

const RendererQueue = @import("render/RendererQueue.zig").RendererQueue;
const Renderer = @import("render/Renderer.zig").Renderer;

pub const FrameData = struct {
    runTime: f32,
    deltaTime: f32,
};

pub const App = struct {
    timeState: TimeState = .{},

    windowQueue: WindowQueue = .{},
    windowData: WindowState,

    inputQueue: InputQueue = .{},
    inputData: InputData = .{},

    entityQueue: EntityQueue = .{},
    entityData: EntityData = .{},

    cameraQueue: CameraQueue = .{},
    cameraData: CameraData = .{},

    rendererQueue: RendererQueue = .{},
    renderer: Renderer,

    memoryMan: *MemoryManager,
    shaderCompiler: ShaderCompiler,
    rng: RNGenerator,

    pub fn init(memoryMan: *MemoryManager) !App {
        var windowState: WindowState = .{};

        WindowSys.init(&windowState) catch |err| {
            std.debug.print("Astral App Error WindowManager could not launch, Err {}\n", .{err});
            return error.WindowManagerFailed;
        };
        errdefer WindowSys.deinit(&windowState);

        var shaderCompiler = ShaderCompiler.init(memoryMan.getAllocator()) catch |err| {
            WindowSys.showErrorBox("Astral App Error", "File Manager could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.ShaderCompilerFailed;
        };
        errdefer shaderCompiler.deinit();

        try shaderCompiler.loadShaders(shaderCon.COMPILING_SHADERS);

        var renderer = Renderer.init(memoryMan) catch |err| {
            WindowSys.showErrorBox("Astral App Error", "Renderer could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.RendererManagerFailed;
        };
        errdefer renderer.deinit();

        return .{
            .windowData = windowState,
            .memoryMan = memoryMan,
            .renderer = renderer,
            .shaderCompiler = shaderCompiler,
            .rng = RNGenerator.init(std.Random.Xoshiro256, 1000),
        };
    }

    pub fn deinit(self: *App) void {
        self.renderer.deinit();
        self.shaderCompiler.deinit();
        WindowSys.deinit(&self.windowData);
        self.memoryMan.deinit();
    }

    pub fn setupApp(self: *App) !void {
        try self.renderer.addShaders(self.shaderCompiler.pullFreshShaders());
        self.shaderCompiler.freeFreshShaders();

        const mainCam = Camera.init(.{ .bufId = rc.cameraUB.id, .pos = zm.f32x4(0, 5, -20, 0), .yaw = 170, .near = 0.1, .far = 100, .fov = 60 });
        const debugCam = Camera.init(.{ .bufId = rc.camera2UB.id, .pos = zm.f32x4(0, 20, -45, 0), .yaw = 170, .near = 0.1, .far = 300, .fov = 110 });
        self.cameraQueue.append(.{ .camAdd = .{ .camId = .{ .val = 0 }, .cam = mainCam } });
        self.cameraQueue.append(.{ .camAdd = .{ .camId = .{ .val = 1 }, .cam = debugCam } });

        for (0..rc.ENTITY_COUNT) |i| self.entityQueue.append(.{ .addRandomEntity = .{ .val = @intCast(i) } });
        EntitySys.update(&self.entityData, &self.entityQueue, &self.rng);

        // RENDERING SET UP
        for (rc.BUFFERS) |bufInf| try self.renderer.addResource(bufInf, null);
        for (rc.TEXTURES) |texInf| self.rendererQueue.append(.{ .addTexture = texInf }); //(texInf, null);
        for (rc.PASSES) |pass| self.rendererQueue.append(.{ .createPass = pass });
        
        try self.renderer.updateBuffer(rc.objectSB.id, EntitySys.getEntitys(&self.entityData));
    }

    pub fn initWindows(self: *App) !void {
        // try WindowSys.addWindow(&self.windowData, "Debug", 1920 / 2, 1080 / 2, rc.quantDebugTex.id, 1920 / 2 - 10, 1080 / 2 - 10, true, &[_]TexId{rc.quantDebugDepthTex.id}, 1);
        // try WindowSys.addWindow(&self.windowData, "Main", 1920 / 2, 1080 / 2, rc.quantTex.id, 10, 40, true, &[_]TexId{rc.quantDepthTex.id}, 0);

        self.windowQueue.append(.{ .addWindow = .{
            .title = "Debug",
            .w = 1920 / 2,
            .h = 1080 / 2,
            .renderTexId = rc.quantDebugTex.id,
            .x = 1920 / 2 - 10,
            .y = 1080 / 2 - 10,
            .resize = true,
            .texIds = &[_]TexId{rc.quantDebugDepthTex.id},
            .camId = .{ .val = 1 },
        } });

        self.windowQueue.append(.{ .addWindow = .{
            .title = "Main",
            .w = 1920 / 2,
            .h = 1080 / 2,
            .renderTexId = rc.quantTex.id,
            .x = 10,
            .y = 40,
            .resize = true,
            .texIds = &[_]TexId{rc.quantDepthTex.id},
            .camId = .{ .val = 0 },
        } });
    }

    pub fn run(self: *App) !void {
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
            WindowSys.pollEvents(&self.windowData, &self.inputQueue, &self.renderer.imguiMan) catch |err| {
                std.log.err("Error in pollEvents(): {}", .{err});
                break;
            };

            // Handle Inputs
            InputSys.update(&self.inputData, &self.inputQueue);
            InputSys.convert(&self.inputData, &self.cameraQueue, &self.windowQueue, &self.rendererQueue);

            try WindowSys.update(&self.windowData, &self.windowQueue, &self.rendererQueue);

            // Close Or Idle
            if (self.windowData.appExit == true) return;
            if (self.windowData.openWindows == 0) continue;

            // Update Time
            TimeSys.update(&self.timeState);
            const dt = TimeSys.getDeltaTime(&self.timeState, .nano, f64);
            frameData.runTime = TimeSys.getRuntime(&self.timeState, .seconds, f32);
            frameData.deltaTime = @floatCast(dt);

            if (rc.CPU_PROFILING == true) std.debug.print("Cpu Delta {d:.3} ms, ({d:.1} Real FPS)\n", .{ dt * 0.000001, 1.0 / (dt * 0.000000001) });

            CameraSys.update(&self.cameraData, &self.cameraQueue, dt, &self.windowData, &self.rendererQueue);

            // Generate and Process and clear Events
            try self.renderer.update(&self.rendererQueue);

            if (firstFrame) WindowSys.showAllWindows(&self.windowData);

            if (rc.EARLY_GPU_WAIT == false) try renderer.waitForGpu();
            // Draw and reset Frame Arena
            renderer.draw(frameData) catch |err| {
                std.log.err("Error in renderer.draw(): {}", .{err});
                break;
            };
            defer self.memoryMan.resetArena();

            if (firstFrame == true) {
                WindowSys.showOpacityAllWindows(&self.windowData);
                firstFrame = false;
            }

            if (rc.CPU_PROFILING or self.renderer.renderGraph.useGpuProfiling or rc.SWAPCHAIN_PROFILING) std.debug.print("\n", .{});
        }
    }
};
