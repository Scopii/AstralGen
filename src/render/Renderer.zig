const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const LoadedShader = @import("../shader/LoadedShader.zig").LoadedShader;
const TextureMeta = @import("types/res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("types/res/BufferMeta.zig").BufferMeta;
const SwapchainMan = @import("sys/SwapchainMan.zig").SwapchainMan;
const ResourceMan = @import("sys/ResourceMan.zig").ResourceMan;
const RenderGraph = @import("sys/RenderGraph.zig").RenderGraph;
const RenderNode = @import("types/pass/PassDef.zig").RenderNode;
const ShaderMan = @import("sys/ShaderMan.zig").ShaderMan;
const Scheduler = @import("sys/Scheduler.zig").Scheduler;
const ImGuiMan = @import("sys/ImGuiMan.zig").ImGuiMan;
const Context = @import("sys/Context.zig").Context;
const rc = @import("../.configs/renderConfig.zig");
const FrameData = @import("../App.zig").FrameData;
const PassDef = @import("types/pass/PassDef.zig").PassDef;
const vk = @import("../.modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const std = @import("std");

const RendererQueue = @import("RendererQueue.zig").RendererQueue;
const EngineData = @import("../EngineData.zig").EngineData;
const Window = @import("../window/Window.zig").Window;

pub const Renderer = struct {
    alloc: Allocator,
    arenaAlloc: Allocator,
    context: Context,
    resMan: ResourceMan,
    renderGraph: RenderGraph,
    shaderMan: ShaderMan,
    swapMan: SwapchainMan,
    scheduler: Scheduler,
    imguiMan: ImGuiMan,
    renderNodes: std.array_list.Managed(RenderNode),

    pub fn init(memoryMan: *MemoryManager) !Renderer {
        const alloc = memoryMan.getAllocator();
        const context = try Context.init(alloc);
        const resMan = try ResourceMan.init(alloc, &context);

        const imguiMan = ImGuiMan.init(&context);

        return .{
            .alloc = alloc,
            .arenaAlloc = memoryMan.getGlobalArena(),
            .context = context,
            .resMan = resMan,
            .renderGraph = try RenderGraph.init(alloc, &context),
            .shaderMan = try ShaderMan.init(&context),
            .scheduler = try Scheduler.init(&context, rc.MAX_IN_FLIGHT),
            .swapMan = try SwapchainMan.init(alloc, &context),
            .renderNodes = std.array_list.Managed(RenderNode).init(alloc),
            .imguiMan = imguiMan,
        };
    }

    pub fn deinit(self: *Renderer) void {
        _ = vk.vkDeviceWaitIdle(self.context.gpi);
        self.imguiMan.deinit();
        self.scheduler.deinit();
        self.swapMan.deinit();
        self.shaderMan.deinit();
        self.resMan.deinit();
        self.renderGraph.deinit();
        self.context.deinit();
        self.renderNodes.deinit();
    }

    pub fn update(self: *Renderer, rendererQueue: *RendererQueue) !void {
        for (rendererQueue.get()) |rendererEvent| {
            switch (rendererEvent) {
                .toggleGpuProfiling => self.renderGraph.toggleGpuProfiling(),
                .updateWindowState => |window| try self.updateWindowStates(&[_]Window{window.*}),
                .addRenderNode => |node| try self.renderNodes.append(node.*),
                .addTexture => |inf| try self.addResource(inf.texInf, inf.data),
                .addBuffer => |inf| try self.addResource(inf.bufInf, inf.data),
                .updateBuffer => |inf| try self.updateBuffer(inf.bufId, inf.data),
                .updateBufferSegment => |inf| try self.updateBufferSegment(inf.bufId, inf.data, inf.elementOffset),
                .addShader => |loadedShader| try self.addShaders(&[_]LoadedShader{loadedShader.*}),
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
                .needCreation => {
                    try self.swapMan.createSwapchain(window, self.renderGraph.cmdMan.cmdPool);
                    try self.imguiMan.addWindowContext(window.id.val, window.handle);
                },
                .needUpdate => try self.swapMan.recreateSwapchain(window.id, window.extent, self.renderGraph.cmdMan.cmdPool),
                .needDelete => {
                    self.imguiMan.removeWindowContext(window.id.val);
                    self.swapMan.removeSwapchains(window.id);
                },
                .needActive, .needInactive => self.swapMan.changeState(window.id, if (window.state == .needActive) true else false),
                else => std.debug.print("Warning: Window State {s} cant be handled in Renderer\n", .{@tagName(window.state)}),
            }

            if (window.resizeTex == true and rc.RENDER_TEX_AUTO_RESIZE and window.state != .needDelete) {
                try self.updateRenderTexture(window.renderTexId);

                for (0..window.linkedTexIds.len) |i| {
                    if (window.linkedTexIds[i] == null) break;
                    const texId = window.linkedTexIds[i].?;
                    try self.updateRenderTexture(texId);
                }
            }
        }
    }

    fn updateRenderTexture(self: *Renderer, texId: TextureMeta.TexId) !void {
        const newExtent = self.swapMan.getMaxExtent(texId);
        try self.resMan.resizeTextureResource(texId, newExtent.width, newExtent.height, self.scheduler.totalFrames, self.scheduler.flightId);
    }

    pub fn waitForGpu(self: *Renderer) !void {
        try self.scheduler.waitForGPU();
    }

    pub fn draw(self: *Renderer, frameData: FrameData, data: *const EngineData, activeWindows: []const Window) !void {
        self.renderNodes.clearRetainingCapacity();
        try self.renderNodes.appendSlice(data.frameBuild.passList.constSlice());

        const flightId = try self.scheduler.beginFrame();
        try self.resMan.update(flightId, self.scheduler.totalFrames);
        try self.swapMan.updateTargets(flightId, activeWindows);

        const cmd = try self.renderGraph.recordFrame(self.renderNodes.items, flightId, self.scheduler.totalFrames, frameData, &self.swapMan, &self.resMan, &self.shaderMan, &self.imguiMan, data);

        const targets = self.swapMan.getTargets();
        try self.scheduler.queueSubmit(cmd, targets, self.context.graphicsQ);
        try self.scheduler.queuePresent(targets, self.context.graphicsQ);

        self.scheduler.endFrame();
    }

    pub fn addShaders(self: *Renderer, loadedShaders: []const LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            if (self.shaderMan.isShaderIdUsed(loadedShader.shaderInf.id.val) == true) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }
        try self.shaderMan.createShaders(loadedShaders, &self.resMan);
    }

    pub fn addResource(self: *Renderer, resInf: anytype, data: anytype) !void {
        try self.resMan.addResource(resInf, self.scheduler.totalFrames, self.scheduler.flightId, data);
    }

    pub fn updateBuffer(self: *Renderer, bufId: BufferMeta.BufId, data: anytype) !void {
        try self.resMan.updateBufferResource(bufId, self.scheduler.totalFrames, self.scheduler.flightId, data);
    }

    pub fn updateBufferSegment(self: *Renderer, bufId: BufferMeta.BufId, data: anytype, element: u32) !void {
        try self.resMan.updateBufferResourceSegment(bufId, self.scheduler.flightId, data, element);
    }
};
