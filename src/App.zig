const TexId = @import("render/types/res/TextureMeta.zig").TextureMeta.TexId;
const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const RNGenerator = @import("core/RNGenerator.zig").RNGenerator;
const shaderCon = @import(".configs/shaderConfig.zig");
const rc = @import(".configs/renderConfig.zig");
const zm = @import("zmath");
const std = @import("std");

const EngineData = @import("EngineData.zig").EngineData;

const TimeSys = @import("time/TimeSys.zig").TimeSys;

const ShaderQueue = @import("shader/ShaderQueue.zig").ShaderQueue;
const ShaderData = @import("shader/ShaderData.zig").ShaderData;
const ShaderSys = @import("shader/ShaderSys.zig").ShaderSys;

const WindowQueue = @import("window/WindowQueue.zig").WindowQueue;
const WindowData = @import("window/WindowData.zig").WindowData;
const WindowSys = @import("window/WindowSys.zig").WindowSys;

const InputQueue = @import("input/InputQueue.zig").InputQueue;
const InputSys = @import("input/InputSys.zig").InputSys;

const CameraSys = @import("camera/CameraSys.zig").CameraSys;

const RenderPrepSys = @import("renderPrep/RenderPrepSys.zig").RenderPrepSys;

const RendererQueue = @import("render/RendererQueue.zig").RendererQueue;
const Renderer = @import("render/Renderer.zig").Renderer;

pub const FrameData = struct {
    runTime: f32,
    deltaTime: f32,
};

pub const App = struct {
    memoryMan: *MemoryManager,
    rng: RNGenerator,

    data: EngineData,

    inputQueue: @import("input/InputQueue.zig").InputQueue = .{},
    shaderQueue: @import("shader/ShaderQueue.zig").ShaderQueue = .{},
    windowQueue: @import("window/WindowQueue.zig").WindowQueue = .{},
    rendererQueue: @import("render/RendererQueue.zig").RendererQueue = .{},

    renderer: Renderer,

    pub fn init(memoryMan: *MemoryManager) !App {
        var data: EngineData = .{};

        WindowSys.init(&data.window) catch |err| {
            std.debug.print("Astral App Error WindowManager could not launch, Err {}\n", .{err});
            return error.WindowManagerFailed;
        };
        errdefer WindowSys.deinit(&data.window);

        ShaderSys.init(&data.shader, memoryMan.getAllocator()) catch |err| {
            WindowSys.showErrorBox("Astral App Error", "File Manager could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.ShaderCompilerFailed;
        };
        errdefer ShaderSys.deinit(&data.shader, memoryMan.getAllocator());

        try ShaderSys.loadShaders(&data.shader, memoryMan.getAllocator(), shaderCon.COMPILING_SHADERS);

        var renderer = Renderer.init(memoryMan) catch |err| {
            WindowSys.showErrorBox("Astral App Error", "Renderer could not launch");
            std.debug.print("Err {}\n", .{err});
            return error.RendererManagerFailed;
        };
        errdefer renderer.deinit();

        return .{
            .data = data,
            .memoryMan = memoryMan,
            .renderer = renderer,
            .rng = RNGenerator.init(std.Random.Xoshiro256, 1000),
        };
    }

    pub fn deinit(self: *App) void {
        self.renderer.deinit();
        ShaderSys.deinit(&self.data.shader, self.memoryMan.getAllocator());
        WindowSys.deinit(&self.data.window);
    }

    pub fn setupEntitys(self: *App) !void {
        try ShaderSys.update(&self.data.shader, &self.shaderQueue, &self.rendererQueue, self.memoryMan);

        const mainCamId = self.data.entityData.createCameraEntity(.{ .pos = zm.f32x4(0, 5, -20, 0), .yaw = 170 }, .{ .bufId = rc.cameraUB.id, .near = 0.1, .far = 100, .fov = 60 });
        const debugCamId = self.data.entityData.createCameraEntity(.{ .pos = zm.f32x4(0, 20, -45, 0), .yaw = 170 }, .{ .bufId = rc.camera2UB.id, .near = 0.1, .far = 300, .fov = 110 });

        for (0..rc.ENTITY_COUNT) |_| _ = self.data.entityData.createRandomRenderEntity(&self.rng);

        self.windowQueue.append(.{
            .addWindow = .{
                .title = "Debug",
                .w = 1920 / 2,
                .h = 1080 / 2,
                .renderTexId = rc.debugTex.id,
                .x = 1920 / 2 - 10,
                .y = 1080 / 2 - 10,
                .resize = true,
                .texIds = &[_]TexId{rc.debugDepthTex.id},
                .camEntityId = debugCamId,
            },
        });

        self.windowQueue.append(.{
            .addWindow = .{
                .title = "Main",
                .w = 1920 / 2,
                .h = 1080 / 2,
                .renderTexId = rc.mainTex.id,
                .x = 10,
                .y = 40,
                .resize = true,
                .texIds = &[_]TexId{rc.mainDepthTex.id},
                .camEntityId = mainCamId,
            },
        });
    }

    pub fn setupResources(self: *App) !void {
        const arena = self.memoryMan.getGlobalArena();

        try ShaderSys.update(&self.data.shader, &self.shaderQueue, &self.rendererQueue, self.memoryMan);

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
    }

    pub fn run(self: *App) !void {
        const renderer = &self.renderer;
        var firstFrame = true;
        var frameData: FrameData = undefined;

        TimeSys.init(&self.data.time);

        while (true) {
            // Shader Hotloading
            if (shaderCon.SHADER_HOTLOAD == true) {
                try ShaderSys.update(&self.data.shader, &self.shaderQueue, &self.rendererQueue, self.memoryMan);
            }

            if (rc.EARLY_GPU_WAIT == true) try renderer.waitForGpu();

            // Poll OS Events
            WindowSys.pollEvents(&self.data.window, &self.inputQueue, &renderer.imguiMan) catch |err| {
                std.log.err("Error in pollEvents(): {}", .{err});
                break;
            };

            // Handle Inputs
            InputSys.update(&self.data.input, &self.inputQueue);
            InputSys.convert(&self.data.input, &self.rendererQueue);

            try WindowSys.update(&self.data.window, &self.data, &self.windowQueue, &self.rendererQueue, self.memoryMan);

            // Close Or Idle
            if (self.data.input.closeApp or self.data.window.appExit) return;
            if (self.data.window.openWindows == 0) continue;

            // Update Time
            TimeSys.update(&self.data.time);
            const dt = TimeSys.getDeltaTime(&self.data.time, .nano, f64);
            frameData.runTime = TimeSys.getRuntime(&self.data.time, .seconds, f32);
            frameData.deltaTime = @floatCast(dt);

            try CameraSys.update(&self.data.entityData, dt, &self.data, &self.rendererQueue, self.memoryMan);

            try RenderPrepSys.extractEntities(&self.data.entityData, &self.rendererQueue, self.memoryMan);

            if (rc.CPU_PROFILING) std.debug.print("Cpu pre-Renderer Delta {d:.3} ms, ({d:.1} Real FPS)\n", .{ dt * 0.000001, 1.0 / (dt * 0.000000001) });

            try self.renderer.update(&self.rendererQueue);

            if (rc.EARLY_GPU_WAIT == false) try renderer.waitForGpu();

            if (firstFrame) WindowSys.showAllWindows(&self.data.window);

            renderer.draw(frameData) catch |err| {
                std.log.err("Error in renderer.draw(): {}", .{err});
                break;
            };

            self.memoryMan.resetArena();
            ShaderSys.freeFreshShaders(&self.data.shader, self.memoryMan.getAllocator()); // SHOULD CHANGE TO USE ARENA

            if (rc.CPU_PROFILING or renderer.renderGraph.useGpuProfiling or rc.SWAPCHAIN_PROFILING) std.debug.print("\n", .{});

            if (firstFrame == true) {
                WindowSys.showOpacityAllWindows(&self.data.window);
                firstFrame = false;
            }
        }
    }
};
