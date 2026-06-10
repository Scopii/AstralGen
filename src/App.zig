const MemoryManager = @import("core/MemoryManager.zig").MemoryManager;
const RNGenerator = @import("core/RNGenerator.zig").RNGenerator;
const EngineData = @import("EngineData.zig").EngineData;
const sc = @import(".configs/shaderConfig.zig");
const rc = @import(".configs/renderConfig.zig");
const zm = @import("zmath");
const std = @import("std");

const TimeSys = @import("time/TimeSys.zig").TimeSys;

const ShaderQueue = @import("shader/ShaderQueue.zig").ShaderQueue;
const ShaderSys = @import("shader/ShaderSys.zig").ShaderSys;

const WindowQueue = @import("window/WindowQueue.zig").WindowQueue;
const WindowSys = @import("window/WindowSys.zig").WindowSys;

const InputQueue = @import("input/InputQueue.zig").InputQueue;
const InputSys = @import("input/InputSys.zig").InputSys;

const CameraSys = @import("camera/CameraSys.zig").CameraSys;

const RenderPrepSys = @import("renderPrep/RenderPrepSys.zig").RenderPrepSys;

const ViewportSys = @import("viewport/ViewportSys.zig").ViewportSys;
const ViewportId = @import("viewport/ViewportSys.zig").ViewportId;
const Viewport = @import("viewport/Viewport.zig").Viewport;

const FrameGraphSys = @import("frameBuild/FrameGraphSys.zig").FrameGraphSys;
const FrameGraphQueue = @import("frameBuild/FrameGraphQueue.zig").FrameGraphQueue;
const pe = @import("frameBuild/enums.zig");

const RendererOutQueue = @import("render/RendererOutQueue.zig").RendererOutQueue;
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

    inputQueue: InputQueue = .{},
    shaderQueue: ShaderQueue = .{},
    windowQueue: WindowQueue = .{},
    frameGraphQueue: FrameGraphQueue = .{},
    rendererQueue: RendererQueue = .{},
    rendererOutQueue: RendererOutQueue = .{},

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

        try ShaderSys.loadShaders(&data.shader, memoryMan.getAllocator(), sc.COMPILING_SHADERS);

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
        UiSys.deinit(&self.data.ui);
        FrameGraphSys.deleteBufferManually(&self.data.frameGraph, .ImguiIB, &self.rendererQueue);
        FrameGraphSys.deleteBufferManually(&self.data.frameGraph, .ImguiVB, &self.rendererQueue);
        FrameGraphSys.deleteTextureManually(&self.data.frameGraph, .ImguiFontTex, &self.rendererQueue);
        self.renderer.deinit();
        ShaderSys.deinit(&self.data.shader, self.memoryMan.getAllocator());
        WindowSys.deinit(&self.data.window);
    }

    pub fn setupEntitys(self: *App) !void {
        try ShaderSys.update(&self.data.shader, &self.shaderQueue, &self.rendererQueue, self.memoryMan);

        for (0..rc.ENTITY_COUNT) |_| _ = self.data.entityData.createRandomRenderEntity(&self.rng);

        const mainCamId = self.data.entityData.createCameraEntity(.{ .pos = zm.f32x4(0, 5, -20, 0), .yaw = 170 }, .{ .bufEnum = .MainCamUB, .near = 0.1, .far = 100, .fov = 60 });
        const debugCamId = self.data.entityData.createCameraEntity(.{ .pos = zm.f32x4(0, 20, -45, 0), .yaw = 170 }, .{ .bufEnum = .DebugCamUB, .near = 0.1, .far = 300, .fov = 110 });

        self.data.viewport.viewports.upsert(10, Viewport{
            .name = "DeptView",
            .cameraEntity = mainCamId,
            .areaX = 0,
            .areaY = 0,
            .areaWidth = 1,
            .areaHeight = 1,
            .passes = &.{
                .DepthView,
            },
            // .blitPass = .DepthView,
        });

        self.windowQueue.append(.{
            .addWindow = .{
                .title = "Depth Window",
                .w = 16 * 55,
                .h = 9 * 55,
                .x = (1920 / 2) / 1 - 10,
                .y = 40,
                .resize = true,
                .texEnums = &[_]pe.TextureEnum{.DepthViewTex},
                .viewIds = [4]?ViewportId{ .{ .val = 10 }, null, null, null },
            },
        });

        self.data.viewport.viewports.upsert(1, Viewport{
            .name = "MainWindow",
            .cameraEntity = mainCamId,
            .areaX = 0.0,
            .areaY = 0.0,
            .areaWidth = 1.0,
            .areaHeight = 1.0,
            .passes = &.{
                .CompTest,
            },
            // .blitPass = .CompTest,
        });

        self.windowQueue.append(.{
            .addWindow = .{
                .title = "Main Window",
                .w = 16 * 55,
                .h = 9 * 55,
                .x = 60,
                .y = 1080 / 2 - 260,
                .resize = true,
                .texEnums = &[_]pe.TextureEnum{.RayMarchInputTex},
                .viewIds = [4]?ViewportId{ .{ .val = 1 }, null, null, null },
            },
        });

        self.data.viewport.viewports.upsert(2, Viewport{
            .name = "Top Right",
            .cameraEntity = mainCamId,
            .areaX = 0.5,
            .areaY = 0.0,
            .areaWidth = 0.5,
            .areaHeight = 0.5,
            .passes = &.{
                .QuantComp,
                .QuantGridMain,
            },
            // .blitPass = .QuantGridMain,
        });

        self.data.viewport.viewports.upsert(3, Viewport{
            .name = "Top Left",
            .cameraEntity = debugCamId,
            .areaX = 0.0,
            .areaY = 0.0,
            .areaWidth = 0.5,
            .areaHeight = 0.5,
            .passes = &.{
                .QuantComp,
                .QuantGridDebug,
                .EditorGridGridDebug,
            },
            // .blitPass = .EditorGrid,
        });
        self.data.viewport.viewports.upsert(4, Viewport{
            .name = "Bot Left",
            .cameraEntity = debugCamId,
            .areaX = 0.0,
            .areaY = 0.5,
            .areaWidth = 0.5,
            .areaHeight = 0.5,
            .passes = &.{
                .QuantComp,
                .QuantPlaneDebug,
                .FrustumView,
                .EditorGridPlaneDebug,
            },
            // .blitPass = .FrustumView,
        });

        self.data.viewport.viewports.upsert(5, Viewport{
            .name = "Bot Right",
            .cameraEntity = mainCamId,
            .areaX = 0.5,
            .areaY = 0.5,
            .areaWidth = 0.5,
            .areaHeight = 0.5,
            .passes = &.{
                .QuantPlaneMain,
            },
            // .blitPass = .QuantPlaneMain,
        });
        self.windowQueue.append(.{
            .addWindow = .{
                .title = "Debug Window",
                .w = 16 * 55,
                .h = 9 * 55,
                .x = 1920 / 2 - 10,
                .y = 1080 / 2 + 40,
                .resize = true,
                .texEnums = &[_]pe.TextureEnum{
                    .GridTex,
                    .GridDepthTex,

                    .DebugGridInputTex,
                    .DebugGridDepthTex,

                    .PlaneTex,
                    .PlaneDepthTex,

                    .DebugPlaneInputTex,
                    .DebugPlaneDepthTex,
                },
                .viewIds = [4]?ViewportId{ .{ .val = 3 }, .{ .val = 2 }, .{ .val = 4 }, .{ .val = 5 } },
            },
        });
    }

    pub fn setupResources(self: *App) !void {
        try ShaderSys.update(&self.data.shader, &self.shaderQueue, &self.rendererQueue, self.memoryMan);
        try FrameGraphSys.createBufferManually(&self.data.frameGraph, .ImguiIB, &self.rendererQueue, self.memoryMan);
        try FrameGraphSys.createBufferManually(&self.data.frameGraph, .ImguiVB, &self.rendererQueue, self.memoryMan);
        try FrameGraphSys.createTextureManually(&self.data.frameGraph, .ImguiFontTex, &self.rendererQueue, self.memoryMan);

        try UiSys.init(&self.data.ui, self.memoryMan);
    }

    pub fn run(self: *App) !void {
        const renderer = &self.renderer;
        var frameData: FrameData = undefined;

        TimeSys.init(&self.data.time);

        const US_PER_FRAME: u64 = std.time.us_per_s / 10;
        var LAST_FRAME: u64 = @intCast(std.time.microTimestamp());
        var US_WAITED: u64 = 0;

        while (true) {
            const CUR_TIME: u64 = @intCast(std.time.microTimestamp());
            const delta = CUR_TIME - LAST_FRAME;
            LAST_FRAME = CUR_TIME;
            US_WAITED += delta;

            if (US_WAITED >= US_PER_FRAME) {
                US_WAITED -= US_PER_FRAME;

                if (sc.SHADER_HOTLOAD == true) try ShaderSys.update(&self.data.shader, &self.shaderQueue, &self.rendererQueue, self.memoryMan);

                if (rc.EARLY_GPU_WAIT == true) try renderer.waitForGpu();

                // Poll OS Events
                WindowSys.pollEvents(&self.data, &self.data.window, &self.inputQueue) catch |err| {
                    std.log.err("Error in pollEvents(): {}", .{err});
                    break;
                };

                // Handle Inputs
                InputSys.update(&self.data.input, &self.inputQueue);
                InputSys.convert(&self.data.input, &self.rendererQueue);

                try WindowSys.update(&self.data.window, &self.data, &self.windowQueue, &self.rendererQueue, self.memoryMan);

                try WindowSys.updateActiveWindows(&self.data.window);

                ViewportSys.update(&self.data.viewport, &self.data);

                // Close Or Idle
                if (self.data.input.closeApp or self.data.window.appExit) return;
                if (self.data.window.openWindows == 0) continue;

                // Update Time
                TimeSys.update(&self.data.time);
                const dt = TimeSys.getDeltaTime(&self.data.time, .nano, f64);
                frameData.runTime = TimeSys.getRuntime(&self.data.time, .seconds, f32);
                frameData.deltaTime = @floatCast(dt);

                try CameraSys.update(&self.data.entityData, dt, &self.data, &self.frameGraphQueue, self.memoryMan);

                try RenderPrepSys.extractEntities(&self.data.entityData, &self.frameGraphQueue, self.memoryMan);

                try UiSys.update(&self.data.ui, &self.data, &self.frameGraphQueue, self.memoryMan);
                const uiNodes = self.data.ui.activeNodes;

                if (rc.CPU_PROFILING) std.debug.print("Cpu pre-Renderer Delta {d:.3} ms, ({d:.1} Real FPS)\n", .{ dt * 0.000001, 1.0 / (dt * 0.000000001) });

                const start = std.time.microTimestamp();
                try FrameGraphSys.build(&self.data.frameGraph, &self.data, &self.rendererQueue, self.memoryMan);
                const end = std.time.microTimestamp();
                std.debug.print("Frame Graph Build: {d:.3} ms\n", .{@as(f64, @floatFromInt(end - start)) / 1_000.0});

                const updateRequests = self.data.frameGraph.resourceAssigner.updateRequests.getConstItems();
                const sortedRenderNodes = self.data.frameGraph.passSorter.sortedRenderNodes.constSlice();
                const bufAssigns = self.data.frameGraph.resourceAssigner.bufAssigns;
                const texAssigns = self.data.frameGraph.resourceAssigner.texAssigns;

                for (updateRequests) |updateRequest| {
                    switch (updateRequest) {
                        .EntityUpdate => {},
                        .CamMainUpdate => {},
                        .CanDebugUpdate => {},
                        .TestTileUpdate => {
                            // PROCEDURAL TEXTURE GENERATION
                            const AddTexPtr = @FieldType(FrameGraphQueue.FrameGraphEvent, "updateTexture");
                            const AddTex = std.meta.Child(AddTexPtr);

                            const arena = self.memoryMan.getGlobalArena();

                            const pixels = try arena.alloc([4]f16, 256 * 256);
                            for (0..256) |y| {
                                for (0..256) |x| {
                                    const isWhite = ((x / 32) + (y / 32)) % 2 == 0;
                                    const val: f16 = if (isWhite) 1.0 else 0.2; // 1.0 (white) or 0.2 (dark)

                                    // RGBA -> Blue checkerboard
                                    pixels[y * 256 + x] = .{ val, val, 1.0, 1.0 };
                                }
                            }

                            const addTextureDataPtr = try arena.create(AddTex);
                            addTextureDataPtr.* = .{ .texEnum = .TestTileTex, .data = std.mem.sliceAsBytes(pixels), .newExtent = null };
                            self.frameGraphQueue.append(.{ .updateTexture = addTextureDataPtr });
                        },
                        .GuiUpdate => {},
                    }
                }

                try FrameGraphSys.processQueue(&self.data.frameGraph, &self.frameGraphQueue, &self.rendererQueue, self.memoryMan);

                try self.renderer.update(&self.rendererQueue, &texAssigns);

                if (rc.EARLY_GPU_WAIT == false) try renderer.waitForGpu();

                renderer.draw(frameData, sortedRenderNodes, uiNodes, &bufAssigns, &texAssigns, self.data.window.activeWindows.constSlice(), &self.rendererOutQueue) catch |err| {
                    std.log.err("Error in renderer.submitDraw(): {}", .{err});
                    break;
                };

                WindowSys.showPresentedWindows(&self.data.window, &self.rendererOutQueue);

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
