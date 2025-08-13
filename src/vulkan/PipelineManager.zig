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
    const pipelineTypes = @typeInfo(PipelineType).@"enum".fields.len;
    pipelines: [pipelineTypes]PipelineBucket, // not used yet
    alloc: Allocator,
    gpi: c.VkDevice,
    cache: c.VkPipelineCache,

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !PipelineManager {
        const gpi = context.gpi;
        const cache = try createPipelineCache(gpi);
        const format = config.RENDER_IMAGE_FORMAT;

        //const pipelines: [pipelineTypes]PipelineBucket = undefined;
        const pipelines1 = try PipelineBucket.init(alloc, gpi, cache, format, &config.computeInf, .compute, resourceManager.layout, 1);
        const pipelines2 = try PipelineBucket.init(alloc, gpi, cache, format, &config.graphicsInf, .graphics, null, 0);
        const pipelines3 = try PipelineBucket.init(alloc, gpi, cache, format, &config.meshShaderInf, .mesh, null, 0);
        const pipelines = .{ pipelines1, pipelines2, pipelines3 };

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .pipelines = pipelines,
            .cache = cache,
        };
    }

    pub fn updatePipeline(self: *PipelineManager, pipeType: PipelineType) !void {
        try self.pipelines[@intFromEnum(pipeType)].updatePipeline(self.gpi, self.cache);
    }

    pub fn deinit(self: *PipelineManager) void {
        const gpi = self.gpi;

        for (0..self.pipelines.len) |i| {
            self.pipelines[i].deinit(gpi);
        }
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
