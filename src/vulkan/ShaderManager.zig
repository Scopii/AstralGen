const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const ztracy = @import("ztracy");
const config = @import("../config.zig");
const Context = @import("Context.zig").Context;
const RenderType = @import("../config.zig").RenderType;
const ShaderLayout = @import("../config.zig").ShaderLayout;
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

    alloc: Allocator,
    descLayout: c.VkDescriptorSetLayout,
    layout: c.VkPipelineLayout,
    shaderObjects: [renderSeqLen]std.ArrayList(ShaderObject),
    renderTypes: [renderSeqLen]RenderType,
    gpi: c.VkDevice,

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !ShaderManager {
        const gpi = context.gpi;
        const layout = try createPipelineLayout(gpi, resourceManager.layout, c.VK_SHADER_STAGE_ALL, @sizeOf(PushConstants));
        var shaderObjects: [renderSeqLen]std.ArrayList(ShaderObject) = undefined;
        var renderTypes: [renderSeqLen]RenderType = undefined;

        for (0..renderSeqLen) |i| {
            const renderType = try checkShaderLayout(config.renderSeq[i]);
            renderTypes[i] = renderType;
            shaderObjects[i] = try initShaderObjects(alloc, gpi, config.renderSeq[i].shaders, resourceManager.layout, renderType);
        }

        return .{
            .alloc = alloc,
            .descLayout = resourceManager.layout,
            .layout = layout,
            .gpi = gpi,
            .shaderObjects = shaderObjects,
            .renderTypes = renderTypes,
        };
    }

    pub fn getRenderType(self: *ShaderManager, sequenceIndex: usize) RenderType {
        return self.renderTypes[sequenceIndex];
    }

    fn checkShaderLayoutOrder(shaderLayout: ShaderLayout) bool {
        var maxStages: [8]i8 = undefined;

        for (0..shaderLayout.shaders.len) |i| {
            switch (shaderLayout.shaders[i].stage) {
                c.VK_SHADER_STAGE_COMPUTE_BIT => maxStages[i] = 0,
                c.VK_SHADER_STAGE_VERTEX_BIT => maxStages[i] = 1,
                c.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT => maxStages[i] = 2,
                c.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT => maxStages[i] = 3,
                c.VK_SHADER_STAGE_GEOMETRY_BIT => maxStages[i] = 4,
                c.VK_SHADER_STAGE_TASK_BIT_EXT => maxStages[i] = 5,
                c.VK_SHADER_STAGE_MESH_BIT_EXT => maxStages[i] = 6,
                c.VK_SHADER_STAGE_FRAGMENT_BIT => maxStages[i] = 7,
                else => std.debug.print("ShaderManager: Shader Stage is Unknown", .{}),
            }
        }
        var temp: i8 = -1;
        for (0..shaderLayout.shaders.len) |i| {
            if (temp <= maxStages[i]) temp = maxStages[i] else return false;
        }
        return true;
    }

    pub fn checkShaderLayout(shaderLayout: ShaderLayout) !RenderType {
        var stage: [8]u8 = .{0} ** 8; // comp, vert, tessControl, tessEval, geo, task, mesh, frag
        const layoutLength = shaderLayout.shaders.len;
        if (checkShaderLayoutOrder(shaderLayout) == false) return error.ShaderLayoutOrderInvalid;

        for (shaderLayout.shaders) |shader| {
            switch (shader.stage) {
                c.VK_SHADER_STAGE_COMPUTE_BIT => stage[0] += 1,
                c.VK_SHADER_STAGE_VERTEX_BIT => stage[1] += 1,
                c.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT => stage[2] += 1,
                c.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT => stage[3] += 1,
                c.VK_SHADER_STAGE_GEOMETRY_BIT => stage[4] += 1,
                c.VK_SHADER_STAGE_TASK_BIT_EXT => stage[5] += 1,
                c.VK_SHADER_STAGE_MESH_BIT_EXT => stage[6] += 1,
                c.VK_SHADER_STAGE_FRAGMENT_BIT => stage[7] += 1,
                else => std.debug.print("ShaderManager: Shader Stage is Unknown", .{}),
            }
        }
        if (layoutLength == 1) {
            if (stage[0] == 1) return .compute;
            if (stage[1] == 1) return .vertOnly;
        }
        if (layoutLength == 3 and stage[5] == 1 and stage[6] == 1 and stage[7] == 1) return .taskMesh;
        if (layoutLength == 2 and stage[6] == 1 and stage[7] == 1) return .mesh;
        if (stage[1] == 1 and stage[2] <= 1 and stage[3] <= 1 and stage[4] <= 1 and stage[5] == 0 and stage[6] == 0 and stage[7] == 1) return .graphics;

        return error.ShaderLayoutInvalid;
    }

    pub fn update(self: *ShaderManager, index: usize) !void {
        const renderType = try checkShaderLayout(config.renderSeq[index]);
        for (self.shaderObjects[index].items) |*shaderObject| shaderObject.deinit(self.gpi);
        self.shaderObjects[index] = try initShaderObjects(self.alloc, self.gpi, config.renderSeq[index].shaders, self.descLayout, renderType);
    }

    pub fn deinit(self: *ShaderManager) void {
        const gpi = self.gpi;

        for (self.shaderObjects) |shaderObjectList| {
            for (shaderObjectList.items) |*shaderObject| shaderObject.deinit(gpi);
            shaderObjectList.deinit();
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

fn createPipelineLayout(gpi: c.VkDevice, descLayout: c.VkDescriptorSetLayout, pushConstantStages: c.VkShaderStageFlags, pushConstantSize: u32) !c.VkPipelineLayout {
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
        .setLayoutCount = if (descLayout != null) @as(u32, 1) else 0,
        .pSetLayouts = if (descLayout != null) &descLayout else null,
        .pushConstantRangeCount = pushConstantRangeCount,
        .pPushConstantRanges = pushConstantRanges,
    };

    var layout: c.VkPipelineLayout = undefined;
    try check(c.vkCreatePipelineLayout(gpi, &pipeLayoutInf, null, &layout), "Failed to create pipeline layout");
    return layout;
}
