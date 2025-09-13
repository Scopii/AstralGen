const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const check = @import("error.zig").check;
const joinPath = @import("../core/FileManager.zig").joinPath;
const resolveProjectRoot = @import("../core/FileManager.zig").resolveProjectRoot;

pub const PipelineType = enum { compute, graphics, mesh };

pub const ShaderInfo = struct {
    pipeType: PipelineType,
    stage: c.VkShaderStageFlagBits,
    glslFile: []const u8,
    spvFile: []const u8,
};

pub const ComputePushConstants = extern struct {
    camPosAndFov: [4]f32,
    camDir: [4]f32,
    runtime: f32,
    dataCount: u32,
    dataAddress: u64,
};

pub const ShaderPipeline = struct {
    layout: c.VkPipelineLayout,
    pipeInf: []const ShaderInfo,
    descLayout: c.VkDescriptorSetLayout,
    shaderObjects: std.ArrayList(ShaderObject),

    pub fn init(alloc: Allocator, gpi: c.VkDevice, pipeInfos: []const ShaderInfo, descLayout: c.VkDescriptorSetLayout, pipeType: PipelineType) !ShaderPipeline {
        if (pipeType == .compute and pipeInfos.len > 1) {
            std.log.err("ShaderPipeline: Compute only supports 1 Stage", .{});
            return error.ShaderStageOverflow;
        }

        const layout = switch (pipeType) {
            .compute => try createPipelineLayout(gpi, descLayout, pipeInfos[0].stage, @sizeOf(ComputePushConstants)),
            .graphics, .mesh => try createPipelineLayout(gpi, descLayout, 0, 0),
        };

        var shaderObjects = std.ArrayList(ShaderObject).init(alloc);

        for (0..pipeInfos.len) |i| {
            const pipeInf = pipeInfos[i];
            const nextStage = if (i + 1 <= pipeInfos.len - 1) pipeInfos[i + 1].stage else 0;
            const shaderObj = try ShaderObject.init(gpi, pipeInf, nextStage, alloc, descLayout, pipeType);
            shaderObjects.append(shaderObj) catch |err| {
                std.debug.print("ShaderPipeline: Could not append ShaderObject, err {}\n", .{err});
                return error.ShaderAppend;
            };
        }

        return .{
            .layout = layout,
            .pipeInf = pipeInfos,
            .shaderObjects = shaderObjects,
            .descLayout = descLayout,
        };
    }

    pub fn deinit(self: *ShaderPipeline, gpi: c.VkDevice) void {
        for (self.shaderObjects.items) |*shaderObject| shaderObject.deinit(gpi);
        c.vkDestroyPipelineLayout(gpi, self.layout, null);
        self.shaderObjects.deinit();
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
