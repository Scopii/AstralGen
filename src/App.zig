const TexId = @import("render/types/res/TextureMeta.zig").TextureMeta.TexId;
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

const ShaderQueue = @import("shader/ShaderQueue.zig").ShaderQueue;
const ShaderData = @import("shader/ShaderData.zig").ShaderData;
const ShaderSys = @import("shader/ShaderSys.zig").ShaderSys;

const WindowQueue = @import("window/WindowQueue.zig").WindowQueue;
const WindowData = @import("window/WindowData.zig").WindowData;
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
    memoryMan: *MemoryManager,
    rng: RNGenerator,
    timeState: TimeState = .{},

    shaderQueue: ShaderQueue = .{},
    shaderData: ShaderData = .{},

    windowQueue: WindowQueue = .{},
    windowData: WindowData,

    inputQueue: InputQueue = .{},
    inputData: InputData = .{},

    entityQueue: EntityQueue = .{},
    entityData: EntityData = .{},

    cameraQueue: CameraQueue = .{},
    cameraData: CameraData = .{},

    rendererQueue: RendererQueue = .{},
    renderer: Renderer,

    pub fn init(memoryMan: *MemoryManager) !App {
        var windowState: WindowData = .{};

        WindowSys.init(&windowState) catch |err| {
            std.debug.print("Astral App Error WindowManager could not launch, Err {}\n", .{err});
            return error.WindowManagerFailed;
        };
        errdefer WindowSys.deinit(&windowState);

        var shaderData: ShaderData = .{};
        ShaderSys.init(&shaderData, memoryMan.getAllocator()) catch |err| {
            WindowSys.showErrorBox("Astral App Error", "File Manager could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.ShaderCompilerFailed;
        };
        errdefer ShaderSys.deinit(&shaderData, memoryMan.getAllocator());

        try ShaderSys.loadShaders(&shaderData, memoryMan.getAllocator(), shaderCon.COMPILING_SHADERS);

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
            .shaderData = shaderData,
            .rng = RNGenerator.init(std.Random.Xoshiro256, 1000),
        };
    }

    pub fn deinit(self: *App) void {
        self.renderer.deinit();
        ShaderSys.deinit(&self.shaderData, self.memoryMan.getAllocator());
        WindowSys.deinit(&self.windowData);
        self.memoryMan.deinit();
    }

    pub fn setupApp(self: *App) !void {
        const arena = self.memoryMan.getGlobalArena();

        try ShaderSys.update(&self.shaderData, &self.shaderQueue, &self.rendererQueue, self.memoryMan);

        const CamAddPtr = @FieldType(CameraQueue.CameraEvent, "camAdd");
        const CamAdd = std.meta.Child(CamAddPtr);

        const mainCam = Camera.init(.{ .bufId = rc.cameraUB.id, .pos = zm.f32x4(0, 5, -20, 0), .yaw = 170, .near = 0.1, .far = 100, .fov = 60 });
        const camAddPtr = try arena.create(CamAdd);
        camAddPtr.* = .{ .camId = .{ .val = 0 }, .cam = mainCam };
        self.cameraQueue.append(.{ .camAdd = camAddPtr });

        const debugCam = Camera.init(.{ .bufId = rc.camera2UB.id, .pos = zm.f32x4(0, 20, -45, 0), .yaw = 170, .near = 0.1, .far = 300, .fov = 110 });
        const cam2AddPtr = try arena.create(CamAdd);
        cam2AddPtr.* = .{ .camId = .{ .val = 1 }, .cam = debugCam };
        self.cameraQueue.append(.{ .camAdd = cam2AddPtr });

        for (0..rc.ENTITY_COUNT) |i| self.entityQueue.append(.{ .addRandomEntity = .{ .val = @intCast(i) } });
        EntitySys.update(&self.entityData, &self.entityQueue, &self.rng);

        // RENDERING SET UP
        for (rc.BUFFERS) |bufInf| {
            const AddBufPtr = @FieldType(RendererQueue.RendererEvent, "addBuffer");
            const AddBuf = std.meta.Child(AddBufPtr);

            const bufferPtr = try arena.create(AddBuf);
            bufferPtr.* = .{ .bufInf = bufInf, .data = null };
            self.rendererQueue.append(.{ .addBuffer = bufferPtr });
        }

        for (rc.TEXTURES) |texInf| {
            const AddTexPtr = @FieldType(RendererQueue.RendererEvent, "addTexture");
            const AddTex = std.meta.Child(AddTexPtr);

            const addTextureDataPtr = try arena.create(AddTex);
            addTextureDataPtr.* = .{ .texInf = texInf, .data = null };
            self.rendererQueue.append(.{ .addTexture = addTextureDataPtr });
        }

        for (rc.PASSES) |*pass| {
            const AddPassPtr = @FieldType(RendererQueue.RendererEvent, "addPass");
            const AddPass = std.meta.Child(AddPassPtr);

            const addPassDataPtr = try arena.create(AddPass);
            addPassDataPtr.* = pass.*;
            self.rendererQueue.append(.{ .addPass = addPassDataPtr });
        }

        // Entity Upload
        const entityData = EntitySys.getEntitys(&self.entityData);
        const slice = try self.memoryMan.arenaAllocUpload(entityData);

        const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBuffer");
        const Payload = std.meta.Child(PayloadPtr);

        const updateBufferPtr = try self.memoryMan.getGlobalArena().create(Payload);
        updateBufferPtr.* = .{ .bufId = rc.objectSB.id, .data = slice };
        self.rendererQueue.append(.{ .updateBuffer = updateBufferPtr });
    }

    pub fn initWindows(self: *App) !void {
        self.windowQueue.append(.{ .addWindow = .{
            .title = "Debug",
            .w = 1920 / 2,
            .h = 1080 / 2,
            .renderTexId = rc.debugTex.id,
            .x = 1920 / 2 - 10,
            .y = 1080 / 2 - 10,
            .resize = true,
            .texIds = &[_]TexId{rc.debugDepthTex.id},
            .camId = .{ .val = 1 },
        } });

        self.windowQueue.append(.{ .addWindow = .{
            .title = "Main",
            .w = 1920 / 2,
            .h = 1080 / 2,
            .renderTexId = rc.mainTex.id,
            .x = 10,
            .y = 40,
            .resize = true,
            .texIds = &[_]TexId{rc.mainDepthTex.id},
            .camId = .{ .val = 0 },
        } });
    }

    pub fn run(self: *App) !void {
        const renderer = &self.renderer;
        var firstFrame = true;
        var frameData: FrameData = undefined;

        while (true) {
            // Shader Hotloading
            if (shaderCon.SHADER_HOTLOAD == true) {
                try ShaderSys.update(&self.shaderData, &self.shaderQueue, &self.rendererQueue, self.memoryMan);
            }

            if (rc.EARLY_GPU_WAIT == true) try renderer.waitForGpu();

            // Poll OS Events
            WindowSys.pollEvents(&self.windowData, &self.inputQueue, &renderer.imguiMan) catch |err| {
                std.log.err("Error in pollEvents(): {}", .{err});
                break;
            };

            // Handle Inputs
            InputSys.update(&self.inputData, &self.inputQueue);
            InputSys.convert(&self.inputData, &self.cameraQueue, &self.windowQueue, &self.rendererQueue);

            try WindowSys.update(&self.windowData, &self.windowQueue, &self.rendererQueue, self.memoryMan);

            // Close Or Idle
            if (self.windowData.appExit == true) return;
            if (self.windowData.openWindows == 0) continue;

            // Update Time
            TimeSys.update(&self.timeState);
            const dt = TimeSys.getDeltaTime(&self.timeState, .nano, f64);
            frameData.runTime = TimeSys.getRuntime(&self.timeState, .seconds, f32);
            frameData.deltaTime = @floatCast(dt);

            try CameraSys.update(&self.cameraData, &self.cameraQueue, dt, &self.windowData, &self.rendererQueue, self.memoryMan);

            if (rc.CPU_PROFILING) std.debug.print("Cpu pre-Renderer Delta {d:.3} ms, ({d:.1} Real FPS)\n", .{ dt * 0.000001, 1.0 / (dt * 0.000000001) });

            try self.renderer.update(&self.rendererQueue);

            if (rc.EARLY_GPU_WAIT == false) try renderer.waitForGpu();

            if (firstFrame) WindowSys.showAllWindows(&self.windowData);

            renderer.draw(frameData) catch |err| {
                std.log.err("Error in renderer.draw(): {}", .{err});
                break;
            };

            self.memoryMan.resetArena();
            ShaderSys.freeFreshShaders(&self.shaderData, self.memoryMan.getAllocator()); // SHOULD CHANGE TO USE ARENA

            if (rc.CPU_PROFILING or renderer.renderGraph.useGpuProfiling or rc.SWAPCHAIN_PROFILING) std.debug.print("\n", .{});

            if (firstFrame == true) {
                WindowSys.showOpacityAllWindows(&self.windowData);
                firstFrame = false;
            }
        }
    }
};
