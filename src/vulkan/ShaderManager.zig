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
    pipeLayout: c.VkPipelineLayout,
    shaderObjects: [renderSeqLen]std.ArrayList(ShaderObject),
    renderTypes: [renderSeqLen]RenderType,
    gpi: c.VkDevice,

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !ShaderManager {
        const gpi = context.gpi;
        const pipeLayout = try createPipelineLayout(gpi, resourceManager.descLayout, c.VK_SHADER_STAGE_ALL, @sizeOf(PushConstants));
        var shaderObjects: [renderSeqLen]std.ArrayList(ShaderObject) = undefined;
        var renderTypes: [renderSeqLen]RenderType = undefined;

        for (0..renderSeqLen) |i| {
            const renderPass = config.renderSeq[i];
            const renderType = try checkShaderLayout(renderPass);
            std.debug.print("ShaderLayout {} renderType {s} windowChannel {s} set\n", .{ i, @tagName(renderType), @tagName(renderPass.channel) });
            shaderObjects[i] = try initShaderObjects(alloc, gpi, renderPass.shaders, resourceManager.descLayout, renderType);
            renderTypes[i] = renderType;
        }

        return .{
            .alloc = alloc,
            .descLayout = resourceManager.descLayout,
            .pipeLayout = pipeLayout,
            .gpi = gpi,
            .shaderObjects = shaderObjects,
            .renderTypes = renderTypes,
        };
    }

    pub fn getRenderType(self: *ShaderManager, sequenceIndex: usize) RenderType {
        return self.renderTypes[sequenceIndex];
    }

    pub fn checkShaderLayout(shaderLayout: ShaderLayout) !RenderType {
        var stages: [8]u8 = .{0} ** 8;
        var prevIndex: i8 = -1;

        for (shaderLayout.shaders) |shader| {
            const curIndex: i8 = switch (shader.stage) {
                c.VK_SHADER_STAGE_COMPUTE_BIT => 0,
                c.VK_SHADER_STAGE_VERTEX_BIT => 1,
                c.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT => 2,
                c.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT => 3,
                c.VK_SHADER_STAGE_GEOMETRY_BIT => 4,
                c.VK_SHADER_STAGE_TASK_BIT_EXT => 5,
                c.VK_SHADER_STAGE_MESH_BIT_EXT => 6,
                c.VK_SHADER_STAGE_FRAGMENT_BIT => 7,
                else => return error.UnknownShaderStage,
            };
            if (curIndex <= prevIndex) return error.ShaderLayoutOrderInvalid;
            prevIndex = curIndex;
            stages[@intCast(curIndex)] += 1;
        }
        switch (shaderLayout.shaders.len) {
            1 => if (stages[0] == 1) return .compute else if (stages[1] == 1) return .vertOnly,
            2 => if (stages[6] == 1 and stages[7] == 1) return .mesh,
            3 => if (stages[5] == 1 and stages[6] == 1 and stages[7] == 1) return .taskMesh,
            else => {},
        }
        if (stages[1] == 1 and stages[2] <= 1 and stages[3] <= 1 and stages[4] <= 1 and stages[5] == 0 and stages[6] == 0 and stages[7] == 1) return .graphics;
        if (stages[2] != stages[3]) return error.ShaderLayoutTessellationMismatch;
        return error.ShaderLayoutInvalid;
    }

    pub fn update(self: *ShaderManager, index: usize) !void {
        const renderPass = config.renderSeq[index];
        const renderType = try checkShaderLayout(renderPass);
        std.debug.print("ShaderLayout {} renderType {s} windowChannel {s} set\n", .{ index, @tagName(renderType), @tagName(renderPass.channel) });

        var list = &self.shaderObjects[index];
        for (list.items) |*shaderObject| shaderObject.deinit(self.gpi);
        list.deinit();

        self.shaderObjects[index] = try initShaderObjects(self.alloc, self.gpi, config.renderSeq[index].shaders, self.descLayout, renderType);
        self.renderTypes[index] = renderType;
    }

    pub fn deinit(self: *ShaderManager) void {
        const gpi = self.gpi;

        for (self.shaderObjects) |shaderObjectList| {
            for (shaderObjectList.items) |*shaderObject| shaderObject.deinit(gpi);
            shaderObjectList.deinit();
        }
        c.vkDestroyPipelineLayout(gpi, self.pipeLayout, null);
    }
};

fn initShaderObjects(alloc: Allocator, gpi: c.VkDevice, shaders: []const config.Shader, descLayout: c.VkDescriptorSetLayout, renderType: RenderType) !std.ArrayList(ShaderObject) {
    var shaderObjects = std.ArrayList(ShaderObject).init(alloc);

    for (0..shaders.len) |i| {
        const shader = shaders[i];
        const nextStage = if (i + 1 <= shaders.len - 1) shaders[i + 1].stage else 0;
        const shaderObj = try ShaderObject.init(gpi, shader, nextStage, alloc, descLayout, renderType);
        shaderObjects.append(shaderObj) catch |err| {
            std.debug.print("ShaderManager could not append ShaderObject, err {}\n", .{err});
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
