const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;
const createShaderModule = @import("../shader/shader.zig").createShaderModule;
const ztracy = @import("ztracy");
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const PipelineBucket = @import("PipelineBucket.zig").Pipeline;
const PipelineType = @import("PipelineBucket.zig").PipelineType;
const ShaderInfo = @import("PipelineBucket.zig").ShaderInfo;
const Context = @import("Context.zig").Context;

const computeInfo = [_]ShaderInfo{
    .{ .stage = c.VK_SHADER_STAGE_COMPUTE_BIT, .inputPath = "src/shader/Compute.comp", .outputPath = "zig-out/shader/Compute.spv" },
};
const graphicsInfo = [_]ShaderInfo{
    .{ .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .inputPath = "src/shader/Graphics.frag", .outputPath = "zig-out/shader/Graphics.spv" },
    .{ .stage = c.VK_SHADER_STAGE_VERTEX_BIT, .inputPath = "src/shader/Graphics.vert", .outputPath = "zig-out/shader/Graphics.spv" },
};
const meshShaderPaths = [_]ShaderInfo{
    .{ .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT, .inputPath = "src/shader/Mesh.frag", .outputPath = "zig-out/shader/Mesh.spv" },
    .{ .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT, .inputPath = "src/shader/Mesh.mesh", .outputPath = "zig-out/shader/Mesh.spv" },
};

pub const PipelineManager = struct {
    alloc: Allocator,
    gpi: c.VkDevice,
    graphics: PipelineBucket,
    compute: PipelineBucket,
    mesh: PipelineBucket,
    cache: c.VkPipelineCache,

    pub fn init(alloc: Allocator, context: *const Context, descriptorManager: *const DescriptorManager) !PipelineManager {
        const gpi = context.gpi;
        const cache = try createPipelineCache(gpi);
        const format = c.VK_FORMAT_R16G16B16A16_SFLOAT;

        const computePipeline = try PipelineBucket.init(alloc, gpi, cache, format, &computeInfo, .compute, descriptorManager.computeLayout, 1);
        const graphicsPipeline = try PipelineBucket.init(alloc, gpi, cache, format, &graphicsInfo, .graphics, null, 0);
        const meshPipeline = try PipelineBucket.init(alloc, gpi, cache, format, &meshShaderPaths, .mesh, null, 0);

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .compute = computePipeline,
            .graphics = graphicsPipeline,
            .mesh = meshPipeline,
            .cache = cache,
        };
    }

    pub fn deinit(self: *PipelineManager) void {
        const gpi = self.gpi;
        self.compute.deinit(gpi);
        self.graphics.deinit(gpi);
        self.mesh.deinit(gpi);
        c.vkDestroyPipelineCache(gpi, self.cache, null);
    }

    pub fn checkShaderUpdate(self: *PipelineManager, pipelineType: PipelineType) !void {
        const tracyZ1 = ztracy.ZoneNC(@src(), "checkShaderUpdate", 0x0000FFFF);
        defer tracyZ1.End();

        switch (pipelineType) {
            .graphics => try self.graphics.checkUpdate(self.gpi, self.cache),
            .compute => try self.compute.checkUpdate(self.gpi, self.cache),
            .mesh => try self.mesh.checkUpdate(self.gpi, self.cache),
        }
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
