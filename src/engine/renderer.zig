const std = @import("std");
const c = @import("../c.zig");
const ztracy = @import("ztracy");

const DEBUG_TOGGLE = @import("../settings.zig").DEBUG_TOGGLE;

const check = @import("error.zig").check;

const Context = @import("render/Context.zig").Context;
const Swapchain = @import("render/Swapchain.zig").Swapchain;
const FramePacer = @import("sync/FramePacer.zig").FramePacer;
const VkAllocator = @import("vma.zig").VkAllocator;
const CmdManager = @import("render/CmdManager.zig").CmdManager;
const PipelineManager = @import("render/PipelineManager.zig").PipelineManager;
const ResourceManager = @import("render/ResourceManager.zig").ResourceManager;
const DescriptorManager = @import("render/DescriptorManager.zig").DescriptorManager;
const recCmd = @import("render/CmdManager.zig").recCmd;

pub const MAX_IN_FLIGHT: u8 = 3;

const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    extentPtr: *c.VkExtent2D,
    context: Context,
    resourceMan: ResourceManager,
    descriptorManager: DescriptorManager,
    pipelineMan: PipelineManager,
    swapchain: Swapchain,
    cmdMan: CmdManager,
    pacer: FramePacer,
    fragmentTimeStemp: i128,
    computeTimeStemp: i128,
    descriptorsUpdated: bool,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: *c.VkExtent2D) !Renderer {
        const context = try Context.init(alloc, window, DEBUG_TOGGLE);
        const resourceMan = try ResourceManager.init(&context);
        const swapchain = try Swapchain.init(&resourceMan, alloc, &context, extent);
        const pipelineMan = try PipelineManager.init(alloc, &context, swapchain.surfaceFormat.format);
        const cmdMan = try CmdManager.init(alloc, context.gpi, context.families.graphics, MAX_IN_FLIGHT);
        const pacer = try FramePacer.init(alloc, context.gpi, MAX_IN_FLIGHT);
        const descriptorManager = try DescriptorManager.init(alloc, context.gpi, pipelineMan.compute.descriptorSetLayout, @intCast(swapchain.swapBuckets.len));
        const fragmentTimeStemp = try getFileTimeStamp(alloc, "src/shader/shdr.frag");
        const computeTimeStemp = try getFileTimeStamp(alloc, "src/shader/shdr.comp");

        return .{
            .alloc = alloc,
            .extentPtr = extent,
            .context = context,
            .resourceMan = resourceMan,
            .descriptorManager = descriptorManager,
            .pipelineMan = pipelineMan,
            .swapchain = swapchain,
            .cmdMan = cmdMan,
            .pacer = pacer,
            .fragmentTimeStemp = fragmentTimeStemp,
            .computeTimeStemp = computeTimeStemp,
            .descriptorsUpdated = false,
        };
    }

    pub fn draw(self: *Renderer) !void {
        try self.checkShaderUpdate();

        try self.pacer.waitForGPU(self.context.gpi);

        const frameIndex = self.pacer.curFrame;
        const cmd = self.cmdMan.cmds[frameIndex];

        if (try self.swapchain.acquireImage(self.context.gpi, self.pacer.acqSems[frameIndex]) == false) {
            try self.renewSwapchain();
            return;
        }

        const swapIndex = self.swapchain.index;
        const rendSem = self.swapchain.swapBuckets[swapIndex].rendSem;

        try self.cmdMan.recCmd(cmd, &self.swapchain, &self.pipelineMan.graphics);

        try self.pacer.submitFrame(self.context.graphicsQ, cmd, rendSem);

        if (try self.swapchain.present(self.context.presentQ, rendSem)) {
            try self.renewSwapchain();
            return;
        }

        self.pacer.nextFrame();
    }

    pub fn drawComputeRenderer(self: *Renderer) !void {
        try self.checkComputeShaderUpdate();
        try self.pacer.waitForGPU(self.context.gpi);

        const frameIndex = self.pacer.curFrame;
        const cmd = self.cmdMan.cmds[frameIndex];

        if (try self.swapchain.acquireImage(self.context.gpi, self.pacer.acqSems[frameIndex]) == false) {
            try self.renewSwapchain();
            return;
        }

        // Update descriptors only once when first needed
        if (!self.descriptorsUpdated) {
            self.descriptorManager.updateAllDescriptorSets(self.context.gpi, self.swapchain.renderImage.view);
            self.descriptorsUpdated = true;
        }

        const swapIndex = self.swapchain.index;
        const rendSem = self.swapchain.swapBuckets[swapIndex].rendSem;

        try self.cmdMan.recComputeCmd(cmd, &self.swapchain, &self.pipelineMan.compute, self.descriptorManager.sets[swapIndex]);
        try self.pacer.submitFrame(self.context.graphicsQ, cmd, rendSem);

        if (try self.swapchain.present(self.context.presentQ, rendSem)) {
            try self.renewSwapchain();
            return;
        }

        self.pacer.nextFrame();
    }

    pub fn checkShaderUpdate(self: *Renderer) !void {
        const tracyZ1 = ztracy.ZoneNC(@src(), "checkShaderUpdate", 0x0000FFFF);
        const timeStamp = try getFileTimeStamp(self.alloc, "src/shader/shdr.frag");
        if (timeStamp != self.fragmentTimeStemp) {
            self.fragmentTimeStemp = timeStamp;
            try self.updateGraphics();
            std.debug.print("Shader Updated ^^\n", .{});
            return;
        }
        tracyZ1.End();
    }

    pub fn checkComputeShaderUpdate(self: *Renderer) !void {
        const tracyZ1 = ztracy.ZoneNC(@src(), "checkShaderUpdate", 0x0000FFFF);
        const timeStamp = try getFileTimeStamp(self.alloc, "src/shader/shdr.comp");
        if (timeStamp != self.computeTimeStemp) {
            self.computeTimeStemp = timeStamp;
            try self.updateCompute();
            std.debug.print("Shader Updated ^^\n", .{});
            return;
        }
        tracyZ1.End();
    }

    pub fn renewSwapchain(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        self.swapchain.deinit(self.context.gpi, &self.resourceMan);
        self.swapchain = try Swapchain.init(&self.resourceMan, self.alloc, &self.context, self.extentPtr);
        self.descriptorManager.updateAllDescriptorSets(self.context.gpi, self.swapchain.renderImage.view);
        std.debug.print("Swapchain recreated\n", .{});
    }

    pub fn updateCompute(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.pipelineMan.refreshComputePipeline(self.alloc, self.context.gpi);
    }

    pub fn updateGraphics(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.pipelineMan.refreshGraphicsPipeline(self.alloc, self.context.gpi);
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        self.pacer.deinit(self.alloc, self.context.gpi);
        self.cmdMan.deinit(self.context.gpi);
        self.swapchain.deinit(self.context.gpi, &self.resourceMan);
        self.resourceMan.deinit();
        self.descriptorManager.deinit(self.context.gpi);
        self.pipelineMan.deinit(self.context.gpi);
        self.context.deinit();
    }
};

pub fn getFileTimeStamp(alloc: Allocator, src: []const u8) !i128 {
    // Use the helper to get the full, correct path
    const abs_path = try resolveAssetPath(alloc, src);
    defer alloc.free(abs_path);

    const cwd = std.fs.cwd();
    const stat = try cwd.statFile(abs_path);
    const lastModified: i128 = stat.mtime;
    return lastModified;
}

pub fn resolveAssetPath(alloc: Allocator, asset_path: []const u8) ![]u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exe_dir);

    // Project root (up two levels from zig-out/bin)
    const project_root = try std.fs.path.resolve(alloc, &[_][]const u8{ exe_dir, "..", ".." });
    defer alloc.free(project_root);

    return std.fs.path.join(alloc, &[_][]const u8{ project_root, asset_path });
}
