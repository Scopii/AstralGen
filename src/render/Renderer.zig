const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const LoadedShader = @import("../shader/LoadedShader.zig").LoadedShader;
const TextureMeta = @import("types/res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("types/res/BufferMeta.zig").BufferMeta;
const SwapchainMan = @import("sys/SwapchainMan.zig").SwapchainMan;
const RenderNode = @import("types/pass/RenderNode.zig").RenderNode;
const ResourceMan = @import("sys/ResourceMan.zig").ResourceMan;
const CmdRecorder = @import("sys/CmdRecorder.zig").CmdRecorder;
const ShaderMan = @import("sys/ShaderMan.zig").ShaderMan;
const Scheduler = @import("sys/Scheduler.zig").Scheduler;
const UiNode = @import("types/pass/RenderNode.zig").UiNode;
const Context = @import("sys/Context.zig").Context;
const rc = @import("../.configs/renderConfig.zig");
const FrameData = @import("../App.zig").FrameData;
const vk = @import("../.modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const std = @import("std");

const TextureAssignments = @import("../frameBuild/6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData.TextureAssignments;
const BufferAssignments = @import("../frameBuild/6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData.BufferAssignments;
const RendererOutQueue = @import("RendererOutQueue.zig").RendererOutQueue;
const TextureEnum = @import("../frameBuild/enums.zig").TextureEnum;
const RendererQueue = @import("RendererQueue.zig").RendererQueue;
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
    renderNodes: std.array_list.Managed(RenderNode),

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
            .renderNodes = std.array_list.Managed(RenderNode).init(alloc),
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
        self.renderNodes.deinit();
    }

    pub fn update(self: *Renderer, rendererQueue: *RendererQueue, texAssigns: *const TextureAssignments) !void {
        for (rendererQueue.get()) |rendererEvent| {
            // std.debug.print("Renderer Queue Event: {s}\n", .{@tagName(rendererEvent)});
            switch (rendererEvent) {
                .toggleGpuProfiling => self.renderGraph.toggleGpuProfiling(),
                .updateWindowState => {},
                .addRenderNode => |node| try self.renderNodes.append(node.*),
                .addTexture => |inf| try self.addResource(inf.texInf, inf.data),
                .addBuffer => |inf| try self.addResource(inf.bufInf, inf.data),
                .updateBuffer => |inf| try self.updateBuffer(inf.bufId, inf.data),
                .updateBufferSegment => |inf| try self.updateBufferSegment(inf.bufId, inf.data, inf.elementOffset),
                .updateTexture => |inf| try self.updateTexture(inf.texId, inf.data, inf.newExtent),
                .addShader => |loadedShader| try self.addShaders(&[_]LoadedShader{loadedShader.*}),
                .removeTexture => |texId| try self.removeResource(texId),
                .removeBuffer => |bufId| try self.removeResource(bufId),
            }
        }
        // Has to happen after so that new assignments and resource changes are applied correctly
        for (rendererQueue.get()) |rendererEvent| {
            // std.debug.print("Renderer Queue Event: {s}\n", .{@tagName(rendererEvent)});
            switch (rendererEvent) {
                .updateWindowState => |window| try self.updateWindowStates(&[_]Window{window.*}, texAssigns),
                else => {},
            }
        }
        rendererQueue.clear();
    }

    fn updateWindowStates(self: *Renderer, tempWindows: []const Window, texAssigns: *const TextureAssignments) !void {
        for (tempWindows) |tempWindow| {
            if (tempWindow.state == .needDelete or tempWindow.state == .needUpdate) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }

        for (tempWindows) |window| {
            switch (window.state) {
                .needCreation => try self.swapMan.createSwapchain(window, self.renderGraph.cmdMan.cmdPool),
                .needUpdate => try self.swapMan.recreateSwapchain(window.id, window.extent, self.renderGraph.cmdMan.cmdPool),
                .needDelete => self.swapMan.removeSwapchains(window.id),
                .needActive, .needInactive => self.swapMan.changeState(window.id, if (window.state == .needActive) true else false),
                else => std.debug.print("Warning: Window State {s} cant be handled in Renderer\n", .{@tagName(window.state)}),
            }

            if (window.resizeTex == true and rc.RENDER_TEX_AUTO_RESIZE and window.state != .needDelete) {
                for (0..window.linkedTexEnums.len) |i| {
                    const texEnum = window.linkedTexEnums[i] orelse continue;
                    try self.updateRenderTexture(texEnum, texAssigns);
                }
            }
        }
    }

    fn updateRenderTexture(self: *Renderer, texEnum: TextureEnum, texAssigns: *const TextureAssignments) !void {
        const newExtent = self.swapMan.getMaxExtent(texEnum);
        const texId = if (texAssigns.isKeyUsed(@intFromEnum(texEnum)) == true) texAssigns.getByKey(@intFromEnum(texEnum)) else return error.TextureNotAssigned;
        try self.resMan.resizeTextureResource(texId, newExtent.width, newExtent.height, 1, self.scheduler.totalFrames, self.scheduler.flightId);
    }

    pub fn waitForGpu(self: *Renderer) !void {
        try self.scheduler.waitForGPU();
    }

    pub fn draw(
        self: *Renderer,
        frameData: FrameData,
        renderNodes: []const RenderNode,
        uiNodes: []const UiNode,
        bufAssigns: *const BufferAssignments,
        texAssigns: *const TextureAssignments,
        activeWindows: []const Window,
        rendererOutQueue: *RendererOutQueue,
    ) !void {
        self.renderNodes.clearRetainingCapacity();
        try self.renderNodes.appendSlice(renderNodes);
        for (uiNodes) |uiNode| self.renderNodes.append(.{ .uiNode = uiNode }) catch std.debug.print("Failed to append UiNode\n", .{});

        const flightId = try self.scheduler.beginFrame();
        try self.resMan.update(flightId, self.scheduler.totalFrames);
        try self.swapMan.updateTargets(flightId, activeWindows);

        const cmd = try self.renderGraph.recordFrame(
            self.renderNodes.items,
            flightId,
            self.scheduler.totalFrames,
            frameData,
            &self.swapMan,
            &self.resMan,
            &self.shaderMan,
            self.context.meshTaskSupp,
            bufAssigns,
            texAssigns,
        );

        try self.scheduler.queueSubmit(cmd, &self.swapMan, self.context.graphicsQ);
        try self.scheduler.queuePresent(&self.swapMan, self.context.graphicsQ);

        self.swapMan.incrementHiddenSwapchains(rendererOutQueue);

        self.scheduler.endFrame();
    }

    pub fn addShaders(self: *Renderer, loadedShaders: []const LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            const shaderTyp = loadedShader.shaderInf.typ;
            const isSpecial = if (shaderTyp == .meshNoTask or shaderTyp == .meshWithTask or shaderTyp == .task) true else false;

            if (self.context.meshTaskSupp == false and isSpecial == true) {
                std.debug.print("Mesh/Task Shaders not Supported by Device! Shaders ignored!\n", .{});
                continue;
            }

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

    pub fn removeResource(self: *Renderer, resId: anytype) !void {
        try self.resMan.removeResource(resId, self.scheduler.totalFrames);
    }

    pub fn updateTexture(self: *Renderer, texId: TextureMeta.TexId, data: anytype, newExtent: ?vk.VkExtent3D) !void {
        try self.resMan.updateTextureResource(texId, self.scheduler.totalFrames, self.scheduler.flightId, data, newExtent);
    }

    pub fn updateBufferSegment(self: *Renderer, bufId: BufferMeta.BufId, data: anytype, element: u32) !void {
        try self.resMan.updateBufferResourceSegment(bufId, self.scheduler.flightId, data, element);
    }
};
