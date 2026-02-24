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
            .passes = std.array_list.Managed(Pass).init(alloc),
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
        self.passes.deinit();
    }

    pub fn updateWindowStates(self: *Renderer, tempWindows: []const Window) !void {
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
                    self.swapMan.removeSwapchains(window.id);
                    self.imguiMan.removeWindowContext(window.id.val);
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

    pub fn updateRenderTexture(self: *Renderer, texId: TextureMeta.TexId) !void {
        const texMeta = try self.resMan.getTextureMeta(texId);
        const oldMeta = texMeta.*;

        const tex = try self.resMan.getTexture(texId, 0); // warning! only checks flightId 0!
        const old = tex.extent;
        const new = self.swapMan.getMaxExtent(texId);

        if (new.width != old.width or new.height != old.height) {
            try self.resMan.queueTextureKills(texId);
            try self.resMan.createTexture(.{ .id = texId, .width = new.width, .height = new.height, .depth = 1, .typ = oldMeta.texType, .mem = oldMeta.mem, .update = oldMeta.update });
            std.debug.print("Render Texture (ID {}) recreated {}x{} to {}x{}\n", .{ texId.val, old.width, old.height, new.width, new.height });
        }
    }

    pub fn waitForGpu(self: *Renderer) !void {
        try self.scheduler.waitForGPU();
    }

    pub fn draw(self: *Renderer, frameData: FrameData) !void {
        const flightId = try self.scheduler.beginFrame();
        try self.resMan.update(flightId, self.scheduler.totalFrames + 1);
        const targets = try self.swapMan.getUpdatedTargets(flightId);

        for (targets) |swapchain| {
            self.imguiMan.newFrame(@intCast(swapchain.windowId), swapchain.extent.width, swapchain.extent.height);
            self.imguiMan.drawUi(@intCast(swapchain.windowId));
        }

        const cmd = try self.renderGraph.recordFrame(self.passes.items, flightId, self.scheduler.totalFrames, frameData, targets, &self.resMan, &self.shaderMan, &self.imguiMan);

        try self.scheduler.queueSubmit(cmd, targets, self.context.graphicsQ);
        try self.scheduler.queuePresent(targets, self.context.graphicsQ);

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
        try self.resMan.updateBuffer(bufInf, data, self.scheduler.flightId);
    }

    pub fn createTexture(self: *Renderer, texInfos: []const TextureMeta.TexInf) !void {
        for (texInfos) |texInf| try self.resMan.createTexture(texInf);
    }
};
