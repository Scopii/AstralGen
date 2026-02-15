const MemoryManager = @import("../../core/MemoryManager.zig").MemoryManager;
const LoadedShader = @import("../../core/ShaderCompiler.zig").LoadedShader;
const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const SwapchainMan = @import("SwapchainMan.zig").SwapchainMan;
const ResourceMan = @import("ResourceMan.zig").ResourceMan;
const Window = @import("../../platform/Window.zig").Window;
const RenderGraph = @import("RenderGraph.zig").RenderGraph;
const ShaderMan = @import("ShaderMan.zig").ShaderMan;
const rc = @import("../../configs/renderConfig.zig");
const FrameData = @import("../../App.zig").FrameData;
const Scheduler = @import("Scheduler.zig").Scheduler;
const Pass = @import("../types/base/Pass.zig").Pass;
const ImGuiMan = @import("ImGuiMan.zig").ImGuiMan;
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const zgui = @import("zgui");
const std = @import("std");

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
    passes: std.array_list.Managed(Pass),

    pub fn init(memoryMan: *MemoryManager, mainWindow: *vk.SDL_Window) !Renderer {
        const alloc = memoryMan.getAllocator();
        const context = try Context.init(alloc);
        const resMan = try ResourceMan.init(alloc, &context);

        const imguiMan = try ImGuiMan.init(&context, mainWindow);

        return .{
            .alloc = alloc,
            .arenaAlloc = memoryMan.getGlobalArena(),
            .context = context,
            .resMan = resMan,
            .renderGraph = try RenderGraph.init(alloc, &context),
            .shaderMan = try ShaderMan.init(&context),
            .scheduler = try Scheduler.init(&context, rc.MAX_IN_FLIGHT),
            .swapMan = try SwapchainMan.init(alloc, &context),
            .passes = std.array_list.Managed(Pass).init(alloc),
            .imguiMan = imguiMan,
        };
    }

    pub fn deinit(self: *Renderer) void {
        _ = vk.vkDeviceWaitIdle(self.context.gpi);
        self.imguiMan.deinit(self.context.gpi);
        self.scheduler.deinit();
        self.swapMan.deinit();
        self.shaderMan.deinit();
        self.resMan.deinit();
        self.renderGraph.deinit();
        self.context.deinit();
        self.passes.deinit();
    }

    pub fn updateWindowStates(self: *Renderer, tempWindows: []const Window) !void {
        for (tempWindows) |tempWindow| {
            if (tempWindow.state == .needDelete or tempWindow.state == .needUpdate) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }
        var texIds: [rc.MAX_WINDOWS]?TextureMeta.TexId = .{null} ** rc.MAX_WINDOWS;

        for (tempWindows, 0..) |window, i| {
            switch (window.state) {
                .needCreation => try self.swapMan.createSwapchain(window),
                .needUpdate => try self.swapMan.recreateSwapchain(window.id, window.extent),
                .needDelete => self.swapMan.removeSwapchains(window.id),
                .needActive, .needInactive => self.swapMan.changeState(window.id, if (window.state == .needActive) true else false),
                else => std.debug.print("Warning: Window State {s} cant be handled in Renderer\n", .{@tagName(window.state)}),
            }
            if (window.resizeTex == true) texIds[i] = window.renderTexId;
        }

        if (rc.RENDER_TEX_AUTO_RESIZE == true) {
            for (0..texIds.len) |i| {
                if (texIds[i] == null) break;
                const texId = texIds[i].?;
                try self.updateRenderTexture(texId);
            }
        }
    }

    pub fn updateRenderTexture(self: *Renderer, texId: TextureMeta.TexId) !void {
        const texMeta = try self.resMan.getTexMeta(texId);
        const tex = try self.resMan.getTex(texId, 0);

        const old = tex.extent;
        const oldType = texMeta.texType;
        const new = self.swapMan.getMaxRenderExtent(texId);

        if (new.width != old.width or new.height != old.height) {
            try self.resMan.queueTextureDestruction(texId, self.scheduler.flightId);
            try self.resMan.createTexture(.{ .id = texId, .width = new.width, .height = new.height, .depth = 1, .typ = oldType, .mem = .Gpu, .update = .PerFrame });
            std.debug.print("Render Texture ID {} recreated {}x{} to {}x{}\n", .{ texId.val, old.width, old.height, new.width, new.height });
        }
    }

    pub fn waitForGpu(self: *Renderer) !void {
        try self.scheduler.waitForGPU();
    }

    pub fn draw(self: *Renderer, frameData: FrameData) !void {
        try self.resMan.update(self.scheduler.flightId, self.scheduler.totalFrames + 1); // + 1?

        const flightId = try self.scheduler.beginFrame();
        const targets = try self.swapMan.getUpdatedTargets(flightId);

        self.imguiMan.newFrame();
        self.imguiMan.drawUi();

        const cmd = try self.renderGraph.recordFrame(self.passes.items, flightId, self.scheduler.totalFrames, frameData, targets, &self.resMan, &self.shaderMan, &self.imguiMan);

        try self.scheduler.queueSubmit(cmd, targets, self.context.graphicsQ);
        try self.scheduler.queuePresent(targets, self.context.presentQ);

        self.scheduler.endFrame();
    }

    pub fn createPasses(self: *Renderer, passes: []const Pass) !void {
        for (passes) |pass| {
            if (self.shaderMan.isPassValid(pass) == false) {
                std.debug.print("Error: Pass ShaderLayout does not match Pass Type -> not appended\n", .{});
                return error.PassNotValid;
            }
            try self.passes.append(pass);
        }
    }

    pub fn addShaders(self: *Renderer, loadedShaders: []const LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            if (self.shaderMan.isShaderIdUsed(loadedShader.shaderInf.id.val) == true) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }
        try self.shaderMan.createShaders(loadedShaders, &self.resMan.descMan);
    }

    pub fn createBuffers(self: *Renderer, bufInfos: []const BufferMeta.BufInf) !void {
        for (bufInfos) |bufInf| try self.resMan.createBuffer(bufInf);
    }

    pub fn updateBuffer(self: *Renderer, bufInf: BufferMeta.BufInf, data: anytype) !void {
        try self.resMan.updateBuffer(bufInf, data, @intCast(self.scheduler.totalFrames % @as(u64, rc.MAX_IN_FLIGHT)));
    }

    pub fn createTexture(self: *Renderer, texInfos: []const TextureMeta.TexInf) !void {
        for (texInfos) |texInf| try self.resMan.createTexture(texInf);
    }
};
