const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const ztracy = @import("ztracy");
const config = @import("../config.zig");
const Context = @import("Context.zig").Context;
const ShaderPipeline = @import("PipelineBucket.zig").ShaderPipeline;
const PipelineType = @import("PipelineBucket.zig").PipelineType;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const check = @import("error.zig").check;

pub const PipelineManager = struct {
    const pipeTypes = @typeInfo(PipelineType).@"enum".fields.len;
    pipelines: [pipeTypes]ShaderPipeline,
    alloc: Allocator,
    gpi: c.VkDevice,
    cache: c.VkPipelineCache,

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !PipelineManager {
        const gpi = context.gpi;
        const cache = try createPipelineCache(gpi);

        const compute = try ShaderPipeline.init(alloc, gpi, &config.computePipeInf, resourceManager.layout, .compute);
        const graphics = try ShaderPipeline.init(alloc, gpi, &config.graphicsPipeInf, null, .graphics);
        const mesh = try ShaderPipeline.init(alloc, gpi, &config.meshPipeInf, null, .mesh);

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .pipelines = .{ compute, graphics, mesh },
            .cache = cache,
        };
    }

    pub fn updatePipeline(self: *PipelineManager, pipeType: PipelineType) !void {
        try self.pipelines[@intFromEnum(pipeType)].update(self.gpi, pipeType);
    }

    pub fn deinit(self: *PipelineManager) void {
        const gpi = self.gpi;
        for (0..self.pipelines.len) |i| self.pipelines[i].deinit(gpi);
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
