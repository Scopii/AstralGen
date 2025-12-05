const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const ztracy = @import("ztracy");
const config = @import("../config.zig");
const Context = @import("Context.zig").Context;
const RenderPass = @import("../config.zig").RenderPass;
const RenderType = @import("../config.zig").RenderType;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const check = @import("error.zig").check;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;

pub const PushConstants = extern struct {
    camPosAndFov: [4]f32,
    camDir: [4]f32,
    runtime: f32,
    dataCount: u32,
    dataAddress: u64,
};

pub const ShaderManager = struct {
    const renderSeqLen = config.renderSeq.len;

    descLayout: c.VkDescriptorSetLayout,
    layout: c.VkPipelineLayout,
    shaderObjects: [renderSeqLen]std.ArrayList(ShaderObject),
    alloc: Allocator,
    gpi: c.VkDevice,

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !ShaderManager {
        const gpi = context.gpi;
        const layout = try createPipelineLayout(gpi, resourceManager.layout, c.VK_SHADER_STAGE_ALL, @sizeOf(PushConstants));

        var shaderObjects: [renderSeqLen]std.ArrayList(ShaderObject) = undefined;
        for (0..renderSeqLen) |i| shaderObjects[i] = try initShaderObjects(alloc, gpi, config.renderSeq[i].shaders, resourceManager.layout, config.renderSeq[i].renderType);

        return .{
            .layout = layout,
            .descLayout = resourceManager.layout,
            .alloc = alloc,
            .gpi = gpi,
            .shaderObjects = shaderObjects,
        };
    }

    pub fn update(self: *ShaderManager, index: usize) !void {
        const descLayout = self.descLayout;
        const renderStep = config.renderSeq[index];
        const shaderList = renderStep.shaders;
        const renderType = renderStep.renderType;
        // Deinit and Recreate at index
        deinitShaderObjects(self.shaderObjects[index], self.gpi);
        self.shaderObjects[index] = try initShaderObjects(self.alloc, self.gpi, shaderList, descLayout, renderType);
    }

    pub fn deinit(self: *ShaderManager) void {
        const gpi = self.gpi;
        for (self.shaderObjects) |shaderObjectList| {
            deinitShaderObjects(shaderObjectList, gpi);
        }
        c.vkDestroyPipelineLayout(gpi, self.layout, null);
    }
};

fn initShaderObjects(alloc: Allocator, gpi: c.VkDevice, shaders: []const config.Shader, descLayout: c.VkDescriptorSetLayout, renderType: RenderType) !std.ArrayList(ShaderObject) {
    if (renderType == .compute and shaders.len > 1) {
        std.log.err("ShaderPipeline: Compute only supports 1 Stage", .{});
        return error.ShaderStageOverflow;
    }
    var shaderObjects = std.ArrayList(ShaderObject).init(alloc);

    for (0..shaders.len) |i| {
        const shader = shaders[i];
        const nextStage = if (i + 1 <= shaders.len - 1) shaders[i + 1].stage else 0;
        const shaderObj = try ShaderObject.init(gpi, shader, nextStage, alloc, descLayout, renderType);
        shaderObjects.append(shaderObj) catch |err| {
            std.debug.print("ShaderPipeline: Could not append ShaderObject, err {}\n", .{err});
            return error.ShaderAppend;
        };
    }

    return shaderObjects;
}

fn deinitShaderObjects(list: std.ArrayList(ShaderObject), gpi: c.VkDevice) void {
    for (list.items) |*shaderObject| shaderObject.deinit(gpi);
    list.deinit();
}

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
