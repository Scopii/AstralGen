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
const Pipeline = @import("render/PipelineManager.zig").Pipeline;
const ResourceManager = @import("render/ResourceManager.zig").ResourceManager;
const DescriptorManager = @import("render/DescriptorManager.zig").DescriptorManager;

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
    graphicsTimeStamp: i128,
    computeTimeStamp: i128,
    meshTimeStamp: i128,
    descriptorsUpdated: bool,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: *c.VkExtent2D) !Renderer {
        const context = try Context.init(alloc, window, DEBUG_TOGGLE);
        const resourceMan = try ResourceManager.init(&context);
        const swapchain = try Swapchain.init(&resourceMan, alloc, &context, extent);
        const pipelineMan = try PipelineManager.init(alloc, &context, swapchain.surfaceFormat.format);
        const cmdMan = try CmdManager.init(alloc, context.gpi, context.families.graphics, MAX_IN_FLIGHT);
        const pacer = try FramePacer.init(alloc, context.gpi, MAX_IN_FLIGHT);
        const descriptorManager = try DescriptorManager.init(alloc, context.gpi, pipelineMan.compute.descriptorSetLayout, @intCast(swapchain.swapBuckets.len));

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
            .graphicsTimeStamp = try getFileTimeStamp(alloc, "src/shader/shdr.frag"),
            .computeTimeStamp = try getFileTimeStamp(alloc, "src/shader/shdr.comp"),
            .meshTimeStamp = try getFileTimeStamp(alloc, "src/shader/mesh.frag"),
            .descriptorsUpdated = false,
        };
    }

    pub fn draw(self: *Renderer, pipeline: Pipeline) !void {
        switch (pipeline) {
            .graphics => try self.checkShaderUpdate(pipeline),
            .compute => try self.checkShaderUpdate(pipeline),
            .mesh => {},
        }

        try self.pacer.waitForGPU(self.context.gpi);
        const frameIndex = self.pacer.curFrame;
        const cmd = self.cmdMan.cmds[frameIndex];

        if (try self.swapchain.acquireImage(self.context.gpi, self.pacer.acqSems[frameIndex]) == false) {
            try self.renewSwapchain();
            return;
        }

        if (pipeline == .compute) {
            // Update descriptors only once when first needed
            if (!self.descriptorsUpdated) {
                self.descriptorManager.updateAllDescriptorSets(self.context.gpi, self.swapchain.renderImage.view);
                self.descriptorsUpdated = true;
            }
        }

        const swapIndex = self.swapchain.index;
        const rendSem = self.swapchain.swapBuckets[swapIndex].rendSem;

        switch (pipeline) {
            .graphics => try self.cmdMan.recCmd(cmd, &self.swapchain, &self.pipelineMan.graphics),
            .compute => try self.cmdMan.recComputeCmd(cmd, &self.swapchain, &self.pipelineMan.compute, self.descriptorManager.sets[swapIndex]),
            .mesh => try self.cmdMan.recMeshCmd(cmd, &self.swapchain, &self.pipelineMan.mesh),
        }

        try self.pacer.submitFrame(self.context.graphicsQ, cmd, rendSem);

        if (try self.swapchain.present(self.context.presentQ, rendSem)) {
            try self.renewSwapchain();
            return;
        }

        self.pacer.nextFrame();
    }

    pub fn checkShaderUpdate(self: *Renderer, pipeline: Pipeline) !void {
        const tracyZ1 = ztracy.ZoneNC(@src(), "checkShaderUpdate", 0x0000FFFF);
        defer tracyZ1.End();

        var timeStamp: i128 = undefined;

        switch (pipeline) {
            .graphics => {
                timeStamp = try getFileTimeStamp(self.alloc, "src/shader/shdr.frag");
                if (timeStamp == self.graphicsTimeStamp) return;
                self.graphicsTimeStamp = timeStamp;
            },
            .compute => {
                timeStamp = try getFileTimeStamp(self.alloc, "src/shader/shdr.comp");
                if (timeStamp == self.computeTimeStamp) return;
                self.computeTimeStamp = timeStamp;
            },
            .mesh => {
                timeStamp = try getFileTimeStamp(self.alloc, "src/shader/mesh.frag");
                if (timeStamp == self.meshTimeStamp) return;
                self.meshTimeStamp = timeStamp;
            },
        }
        try self.updatePipeline(pipeline);
        std.debug.print("Shader Updated ^^\n", .{});
    }

    pub fn updatePipeline(self: *Renderer, pipeline: Pipeline) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        switch (pipeline) {
            .graphics => try self.pipelineMan.updateGraphicsPipeline(self.alloc, self.context.gpi),
            .compute => try self.pipelineMan.updateComputePipeline(self.alloc, self.context.gpi),
            .mesh => {},
        }
    }

    pub fn renewSwapchain(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        self.swapchain.deinit(self.context.gpi, &self.resourceMan);
        self.swapchain = try Swapchain.init(&self.resourceMan, self.alloc, &self.context, self.extentPtr);
        self.descriptorManager.updateAllDescriptorSets(self.context.gpi, self.swapchain.renderImage.view);
        std.debug.print("Swapchain recreated\n", .{});
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
    // Using helper to get the full path
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
