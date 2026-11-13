const RenderNodeRing = @import("../renderCompiler/RenderCompilerData.zig").RenderCompilerData.RenderNodeRing;
const RendererOutQueue = @import("RendererOutQueue.zig").RendererOutQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const LoadedShader = @import("../shader/LoadedShader.zig").LoadedShader;
const RenderNode = @import("types/pass/RenderNode.zig").RenderNode;
const SwapchainMan = @import("sys/SwapchainMan.zig").SwapchainMan;
const RendererQueue = @import("RendererQueue.zig").RendererQueue;
const ResourceMan = @import("sys/ResourceMan.zig").ResourceMan;
const CmdRecorder = @import("sys/CmdRecorder.zig").CmdRecorder;
const WindowId = @import("../.configs/idConfig.zig").WindowId;
const UiNode = @import("types/pass/RenderNode.zig").UiNode;
const ShaderMan = @import("sys/ShaderMan.zig").ShaderMan;
const Scheduler = @import("sys/Scheduler.zig").Scheduler;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const Context = @import("sys/Context.zig").Context;
const rc = @import("../.configs/renderConfig.zig");
const FrameData = @import("../App.zig").FrameData;
const vk = @import("../.modules/vk.zig").c;
const std = @import("std");
const Allocator = std.mem.Allocator;

const Window = @import("../window/Window.zig").Window;

pub const Renderer = struct {
    alloc: Allocator,
    arenaAlloc: Allocator,
    context: Context,
    resMan: ResourceMan,
    renderGraph: CmdRecorder,
    shaderMan: ShaderMan,
    swapMan: SwapchainMan,
    scheduler: Scheduler,

    pub fn init(memoryMan: *MemoryManager) !Renderer {
        const alloc = memoryMan.getAllocator();
        const context = try Context.init(alloc);
        const resMan = try ResourceMan.init(alloc, &context);

        return .{
            .alloc = alloc,
            .arenaAlloc = memoryMan.getGlobalArena(),
            .context = context,
            .resMan = resMan,
            .renderGraph = try CmdRecorder.init(alloc, &context),
            .shaderMan = try ShaderMan.init(&context),
            .scheduler = try Scheduler.init(&context, rc.MAX_IN_FLIGHT),
            .swapMan = try SwapchainMan.init(alloc, &context),
        };
    }

    pub fn deinit(self: *Renderer) void {
        _ = vk.vkDeviceWaitIdle(self.context.gpi);
        self.scheduler.deinit();
        self.swapMan.deinit();
        self.shaderMan.deinit();
        self.resMan.deinit();
        self.renderGraph.deinit();
        self.context.deinit();
    }

    pub fn update(self: *Renderer, rendererQueue: *RendererQueue) !void {
        for (0..rendererQueue.length()) |i| {
            const rendererEvent = rendererQueue.get(@intCast(i));
            // std.debug.print("Renderer Queue Event: {s}\n", .{@tagName(rendererEvent)});
            switch (rendererEvent) {
                .toggleGpuProfiling => self.renderGraph.toggleGpuProfiling(),
                .addTexture => |inf| try self.resMan.addTex(inf.texInf, self.scheduler.totalFrames, self.scheduler.flightId, inf.data),
                .addBuffer => |inf| try self.resMan.addBuf(inf.bufInf, self.scheduler.totalFrames, self.scheduler.flightId, inf.data),
                .updateBuffer => |inf| try self.resMan.updateBuf(inf.bufId, self.scheduler.totalFrames, self.scheduler.flightId, inf.data),
                .updateBufferSegment => |inf| try self.resMan.updateBufSegment(inf.bufId, self.scheduler.flightId, inf.data, inf.elementOffset),
                .updateTexture => |inf| try self.resMan.updateTex(inf.texId, self.scheduler.totalFrames, self.scheduler.flightId, inf.data),
                .addShader => |loadedShader| try self.addShaders(&[_]LoadedShader{loadedShader}),
                .removeTexture => |texId| try self.resMan.removeTex(texId, self.scheduler.totalFrames),
                .removeBuffer => |bufId| try self.resMan.removeBuf(bufId, self.scheduler.totalFrames),
                .updateWindowState => |window| try self.updateWindowStates(&[_]Window{window}),
            }
        }
        rendererQueue.clear();
    }

    fn updateWindowStates(self: *Renderer, tempWindows: []const Window) !void {
        for (tempWindows) |tempWindow| {
            if (tempWindow.state == .needDelete or tempWindow.state == .needUpdate) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }

        for (tempWindows) |window| {
            switch (window.state) {
                .needCreation => try self.swapMan.createSwapchain(window),
                .needUpdate => try self.swapMan.recreateSwapchain(window.id, window.extent),
                .needDelete => self.swapMan.removeSwapchains(window.id),
                .needActive, .needInactive => self.swapMan.changeState(window.id, if (window.state == .needActive) true else false),
                else => std.debug.print("Warning: Window State {s} cant be handled in Renderer\n", .{@tagName(window.state)}),
            }
        }
    }

    pub fn waitForGpu(self: *Renderer) !void {
        try self.scheduler.waitForGPU();
    }

    pub fn draw(self: *Renderer, renderNodes: RenderNodeRing, pushData: []const u8, activeWindows: []const WindowId, rendererOutQueue: *RendererOutQueue) !void {
        const flightId = try self.scheduler.beginFrame();
        try self.resMan.update(flightId, self.scheduler.totalFrames);
        try self.swapMan.updateTargets(flightId, activeWindows);

        const cmd = try self.renderGraph.recordFrame(
            &renderNodes,
            flightId,
            self.scheduler.totalFrames,
            &self.swapMan,
            &self.resMan,
            &self.shaderMan,
            self.context.meshTaskSupp,
            pushData,
        );

        try self.scheduler.queueSubmit(cmd, &self.swapMan, self.context.graphicsQ);
        try self.scheduler.queuePresent(&self.swapMan, self.context.graphicsQ);

        self.swapMan.incrementHiddenSwapchains(rendererOutQueue);

        self.scheduler.endFrame();
    }

    fn addShaders(self: *Renderer, loadedShaders: []const LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            const shaderTyp = loadedShader.shaderInf.typ;
            const isSpecial = if (shaderTyp == .meshNoTask or shaderTyp == .meshWithTask or shaderTyp == .task) true else false;

            if (self.context.meshTaskSupp == false and isSpecial == true) {
                std.debug.print("Mesh/Task Shaders not Supported by Device! Shaders ignored!\n", .{});
                continue;
            }

            if (self.shaderMan.isShaderIdUsed(loadedShader.shaderInf.id.val()) == true) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }
        try self.shaderMan.createShaders(loadedShaders, &self.resMan);
    }
};
