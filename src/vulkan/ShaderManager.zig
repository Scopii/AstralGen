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

pub const PushConstants = extern struct {
    camPosAndFov: [4]f32,
    camDir: [4]f32,
    runtime: f32,
    dataCount: u32,
    dataAddress: u64,
};

pub const ShaderManager = struct {
    const pipeTypes = @typeInfo(PipelineType).@"enum".fields.len;

    descLayout: c.VkDescriptorSetLayout,
    layout: c.VkPipelineLayout,
    shaderPipes: [pipeTypes]ShaderPipeline,
    alloc: Allocator,
    gpi: c.VkDevice,

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !ShaderManager {
        const gpi = context.gpi;
        const layout = try createPipelineLayout(gpi, resourceManager.layout, c.VK_SHADER_STAGE_COMPUTE_BIT, @sizeOf(PushConstants));

        var shaderPipes: [pipeTypes]ShaderPipeline = undefined;
        for (0..pipeTypes) |i| shaderPipes[i] = try ShaderPipeline.init(alloc, gpi, config.renderSequence[i], resourceManager.layout, @enumFromInt(i));

        return .{
            .layout = layout,
            .descLayout = resourceManager.layout,
            .alloc = alloc,
            .gpi = gpi,
            .shaderPipes = shaderPipes,
        };
    }

    pub fn update(self: *ShaderManager, pipeType: PipelineType) !void {
        const pipeEnum = @intFromEnum(pipeType);
        const descLayout = self.descLayout;
        const pipeInf = self.shaderPipes[pipeEnum].pipeInf;
        self.shaderPipes[pipeEnum].deinit(self.gpi);
        self.shaderPipes[pipeEnum] = try ShaderPipeline.init(self.alloc, self.gpi, pipeInf, descLayout, pipeType);
    }

    pub fn deinit(self: *ShaderManager) void {
        const gpi = self.gpi;
        for (0..self.shaderPipes.len) |i| self.shaderPipes[i].deinit(gpi);
        c.vkDestroyPipelineLayout(gpi, self.layout, null);
    }
};

fn createPipelineLayout(gpi: c.VkDevice, descriptorLayout: c.VkDescriptorSetLayout, pushConstantStages: c.VkShaderStageFlags, pushConstantSize: u32) !c.VkPipelineLayout {
    var pushConstantRange: c.VkPushConstantRange = undefined;
    var pushConstantRangeCount: u32 = 0;
    var pushConstantRanges: ?*const c.VkPushConstantRange = null;

    if (pushConstantSize > 0) {
        pushConstantRange = c.VkPushConstantRange{
            .stageFlags = pushConstantStages,
            .offset = 0,
            .size = pushConstantSize,
        };
        pushConstantRangeCount = 1;
        pushConstantRanges = &pushConstantRange;
    }

    const pipeLayoutInf = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = if (descriptorLayout != null) @as(u32, 1) else 0,
        .pSetLayouts = if (descriptorLayout != null) &descriptorLayout else null,
        .pushConstantRangeCount = pushConstantRangeCount,
        .pPushConstantRanges = pushConstantRanges,
    };

    var layout: c.VkPipelineLayout = undefined;
    try check(c.vkCreatePipelineLayout(gpi, &pipeLayoutInf, null, &layout), "Failed to create pipeline layout");
    return layout;
}
