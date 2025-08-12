const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;
const ztracy = @import("ztracy");
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const PipelineBucket = @import("PipelineBucket.zig").Pipeline;
const PipelineType = @import("PipelineBucket.zig").PipelineType;
const Context = @import("Context.zig").Context;

const config = @import("../config.zig");

pub const PipelineManager = struct {
    alloc: Allocator,
    gpi: c.VkDevice,
    graphics: PipelineBucket,
    compute: PipelineBucket,
    mesh: PipelineBucket,
    cache: c.VkPipelineCache,

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !PipelineManager {
        const gpi = context.gpi;
        const cache = try createPipelineCache(gpi);
        const format = config.RENDER_IMAGE_FORMAT;

        const computePipe = try PipelineBucket.init(alloc, gpi, cache, format, &config.computeInf, .compute, resourceManager.layout, 1);
        const graphicsPipe = try PipelineBucket.init(alloc, gpi, cache, format, &config.graphicsInf, .graphics, null, 0);
        const meshPipe = try PipelineBucket.init(alloc, gpi, cache, format, &config.meshShaderInf, .mesh, null, 0);

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .compute = computePipe,
            .graphics = graphicsPipe,
            .mesh = meshPipe,
            .cache = cache,
        };
    }

    pub fn updatePipeline(self: *PipelineManager, pipeType: PipelineType) !void {
        switch (pipeType) {
            .compute => try self.compute.updatePipeline(self.gpi, self.cache),
            .graphics => try self.graphics.updatePipeline(self.gpi, self.cache),
            .mesh => try self.mesh.updatePipeline(self.gpi, self.cache),
        }
    }

    pub fn deinit(self: *PipelineManager) void {
        const gpi = self.gpi;
        self.compute.deinit(gpi);
        self.graphics.deinit(gpi);
        self.mesh.deinit(gpi);
        c.vkDestroyPipelineCache(gpi, self.cache, null);
    }
};

fn createPipelineCache(gpi: c.VkDevice) !c.VkPipelineCache {
    const cacheCreateInf = c.VkPipelineCacheCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
        .flags = 0,
        .initialDataSize = 0,
        .pInitialData = null,
    };
    var cache: c.VkPipelineCache = undefined;
    try check(c.vkCreatePipelineCache(gpi, &cacheCreateInf, null, &cache), "Failed to create Pipeline Cache");
    return cache;
}
