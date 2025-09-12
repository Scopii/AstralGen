const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const ztracy = @import("ztracy");
const config = @import("../config.zig");
const Context = @import("Context.zig").Context;
const ShaderPipeline = @import("ShaderPipeline.zig").ShaderPipeline;
const PipelineType = @import("ShaderPipeline.zig").PipelineType;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const check = @import("error.zig").check;

pub const ShaderManager = struct {
    const pipeTypes = @typeInfo(PipelineType).@"enum".fields.len;
    pipelines: [pipeTypes]ShaderPipeline,
    alloc: Allocator,
    gpi: c.VkDevice,

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !ShaderManager {
        const gpi = context.gpi;

        const compute = try ShaderPipeline.init(alloc, gpi, &config.computePipe, resourceManager.layout, .compute);
        const graphics = try ShaderPipeline.init(alloc, gpi, &config.graphicsPipe, null, .graphics);
        const mesh = try ShaderPipeline.init(alloc, gpi, &config.meshPipe, null, .mesh);

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .pipelines = .{ compute, graphics, mesh },
        };
    }

    pub fn update(self: *ShaderManager, pipeType: PipelineType) !void {
        const pipeEnum = @intFromEnum(pipeType);
        const descLayout = self.pipelines[pipeEnum].descLayout;
        const pipeInf = self.pipelines[pipeEnum].pipeInf;
        self.pipelines[pipeEnum].deinit(self.gpi);
        self.pipelines[pipeEnum] = try ShaderPipeline.init(self.alloc, self.gpi, pipeInf, descLayout, pipeType);
    }

    pub fn deinit(self: *ShaderManager) void {
        const gpi = self.gpi;
        for (0..self.pipelines.len) |i| self.pipelines[i].deinit(gpi);
    }
};
