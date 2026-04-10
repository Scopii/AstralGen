const TexId = @import("render/types/res/TextureMeta.zig").TextureMeta.TexId;
const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const RNGenerator = @import("core/RNGenerator.zig").RNGenerator;
const EngineData = @import("EngineData.zig").EngineData;
const shaderCon = @import(".configs/shaderConfig.zig");
const rc = @import(".configs/renderConfig.zig");
const zm = @import("zmath");
const std = @import("std");

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

const ViewportSys = @import("viewport/ViewportSys.zig").ViewportSys;
const ViewportId = @import("viewport/ViewportSys.zig").ViewportId;
const Viewport = @import("viewport/Viewport.zig").Viewport;

const FrameBuildSys = @import("frameBuild/FrameBuildSys.zig").FrameBuildSys;

const RendererQueue = @import("render/RendererQueue.zig").RendererQueue;
const Renderer = @import("render/Renderer.zig").Renderer;

const UiSys = @import("ui/UiSys.zig").UiSys;

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

        const mainCamId = self.data.entityData.createCameraEntity(.{ .pos = zm.f32x4(0, 5, -20, 0), .yaw = 170 }, .{ .bufId = rc.mainCamUB.id, .near = 0.1, .far = 100, .fov = 60 });
        const debugCamId = self.data.entityData.createCameraEntity(.{ .pos = zm.f32x4(0, 20, -45, 0), .yaw = 170 }, .{ .bufId = rc.debugCamUB.id, .near = 0.1, .far = 300, .fov = 110 });

        self.data.viewport.viewports.upsert(1, Viewport{
            .name = "Full Viewport",
            .cameraEntity = mainCamId,
            .sourceTexId = rc.mainTex.id,
            .areaX = 0.0,
            .areaY = 0.0,
            .areaWidth = 1.0,
            .areaHeight = 1.0,
            .passSlice = &.{
                .CompTest,
            },
            .blitPass = .CompTest,
        });

        self.data.viewport.viewports.upsert(2, Viewport{
            .name = "Top Left Viewport",
            .cameraEntity = mainCamId,
            .sourceTexId = rc.mainTex.id,
            .areaX = 0.5,
            .areaY = 0.0,
            .areaWidth = 0.5,
            .areaHeight = 0.5,
            .passSlice = &.{
                .QuantComp,
                .QuantGridMain,
            },
            .blitPass = .QuantGridMain,
        });

        self.data.viewport.viewports.upsert(3, Viewport{
            .name = "Top Right Viewport",
            .cameraEntity = debugCamId,
            .sourceTexId = rc.mainTex.id,
            .areaX = 0.0,
            .areaY = 0.0,
            .areaWidth = 0.5,
            .areaHeight = 0.5,
            .passSlice = &.{
                .QuantComp,
                .QuantGridDebug,
                .EditorGrid,
            },
            .blitPass = .EditorGrid,
        });
        self.data.viewport.viewports.upsert(4, Viewport{
            .name = "Bot Left Viewport",
            .cameraEntity = debugCamId,
            .sourceTexId = rc.mainTex.id,
            .areaX = 0.0,
            .areaY = 0.5,
            .areaWidth = 0.5,
            .areaHeight = 0.5,
            .passSlice = &.{
                .QuantPlaneDebug,
                .FrustumView,
            },
            .blitPass = .FrustumView,
        });

        self.data.viewport.viewports.upsert(5, Viewport{
            .name = "Bot Right Viewport",
            .cameraEntity = mainCamId,
            .sourceTexId = rc.mainTex.id,
            .areaX = 0.5,
            .areaY = 0.5,
            .areaWidth = 0.5,
            .areaHeight = 0.5,
            .passSlice = &.{
                .QuantPlaneMain,
            },
            .blitPass = .QuantPlaneMain,
        });

        for (0..rc.ENTITY_COUNT) |_| _ = self.data.entityData.createRandomRenderEntity(&self.rng);

        self.windowQueue.append(.{
            .addWindow = .{
                .title = "Debug Window",
                .w = 1920 / 2,
                .h = 1080 / 2,
                .renderTexId = rc.mainTex.id,
                .x = 1920 / 2 - 10,
                .y = 1080 / 2 - 10,
                .resize = true,
                .texIds = &[_]TexId{rc.mainDepthTex.id},
                .viewIds = [4]?ViewportId{ .{ .val = 3 }, .{ .val = 2 }, .{ .val = 4 }, .{ .val = 5 } },
            },
        });

        self.windowQueue.append(.{
            .addWindow = .{
                .title = "Main Window",
                .w = 1920 / 2,
                .h = 1080 / 2,
                .renderTexId = rc.mainTex.id,
                .x = 10,
                .y = 40,
                .resize = true,
                .texIds = &[_]TexId{rc.mainDepthTex.id},
                .viewIds = [4]?ViewportId{ .{ .val = 1 }, null, null, null },
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
    }

    pub fn run(self: *App) !void {
        const renderer = &self.renderer;
        var frameData: FrameData = undefined;

        TimeSys.init(&self.data.time);

        const US_PER_FRAME: u64 = std.time.us_per_s / 15000;
        var LAST_FRAME: u64 = @intCast(std.time.microTimestamp());
        var US_WAITED: u64 = 0;

        while (true) {
            const CUR_TIME: u64 = @intCast(std.time.microTimestamp());
            const delta = CUR_TIME - LAST_FRAME;
            LAST_FRAME = CUR_TIME;
            US_WAITED += delta;

            if (US_WAITED >= US_PER_FRAME) {
                US_WAITED -= US_PER_FRAME;

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

                ViewportSys.update(&self.data.viewport, &self.data);

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

                try WindowSys.updateActiveWindows(&self.data.window);

                const activeWindows = self.data.window.activeWindows.constSlice();
                // UI per-window/viewport
                for (activeWindows) |*window| {
                    if (self.data.window.uiActive) {
                        self.renderer.imguiMan.newFrame(window.id.val, window.extent.width, window.extent.height);
                        UiSys.buildWindowUi(window, &self.data);
                    }
                }

                // const start = std.time.microTimestamp();
                FrameBuildSys.build(&self.data.frameBuild, &self.data);
                // const end = std.time.microTimestamp();
                // std.debug.print("Frame Build {d:.3} ms\n", .{@as(f64, @floatFromInt(end - start)) / 1_000.0});

                const start = std.time.microTimestamp();

                // RENDER:
                renderer.draw(frameData, &self.data, activeWindows) catch |err| {
                    std.log.err("Error in renderer.submitDraw(): {}", .{err});
                    break;
                };

                const end = std.time.microTimestamp();
                std.debug.print("Frame Build {d:.3} ms\n", .{@as(f64, @floatFromInt(end - start)) / 1_000.0});

                self.memoryMan.resetArena();
                ShaderSys.freeFreshShaders(&self.data.shader, self.memoryMan.getAllocator()); // SHOULD CHANGE TO USE ARENA

                // if (rc.CPU_PROFILING or renderer.renderGraph.useGpuProfiling or rc.SWAPCHAIN_PROFILING) std.debug.print("\n", .{});

            } else {
                const REMAINING_US = US_PER_FRAME - US_WAITED;
                if (REMAINING_US > 2000) std.Thread.sleep((REMAINING_US - 1000) * 1000);
            }
        }
    }
};
