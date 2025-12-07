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
        for (0..renderSeqLen) |i| shaderObjects[i] = std.ArrayList(ShaderObject).init(alloc);

        errdefer {
            for (0..renderSeqLen) |i| {
                for (shaderObjects[i].items) |*shaderObj| shaderObj.deinit(gpi);
                shaderObjects[i].deinit();
            }
            c.vkDestroyPipelineLayout(gpi, pipeLayout, null);
        }

        var renderTypes: [renderSeqLen]RenderType = undefined;
        for (0..renderSeqLen) |i| {
            const renderPass = config.renderSeq[i];
            renderTypes[i] = try checkShaderLayout(renderPass);
            std.debug.print("ShaderLayout {} renderType {s} windowChannel {s} valid\n", .{ i, @tagName(renderTypes[i]), @tagName(renderPass.channel) });
            shaderObjects[i] = try setShaderLayout(alloc, gpi, resourceManager.descLayout, i, renderTypes[i]);
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

    pub fn getRenderType(self: *ShaderManager, seqIndex: usize) RenderType {
        return self.renderTypes[seqIndex];
    }

    pub fn update(self: *ShaderManager, seqIndex: usize) !void {
        const renderPass = config.renderSeq[seqIndex];
        const renderType = try checkShaderLayout(renderPass);
        std.debug.print("ShaderLayout {} renderType {s} windowChannel {s} updated\n", .{ seqIndex, @tagName(renderType), @tagName(renderPass.channel) });

        const newList = try setShaderLayout(self.alloc, self.gpi, self.descLayout, seqIndex, renderType);

        const list = &self.shaderObjects[seqIndex];
        for (list.items) |*shaderObject| shaderObject.deinit(self.gpi);
        list.deinit();
        list.* = newList;

        self.renderTypes[seqIndex] = renderType;
    }

    pub fn deinit(self: *ShaderManager) void {
        const gpi = self.gpi;

        for (&self.shaderObjects) |*shaderObjList| {
            for (shaderObjList.items) |*shaderObj| shaderObj.deinit(gpi);
            shaderObjList.deinit();
        }
        c.vkDestroyPipelineLayout(gpi, self.pipeLayout, null);
    }
};

fn checkShaderLayout(shaderLayout: ShaderLayout) !RenderType {
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

fn setShaderLayout(alloc: Allocator, gpi: c.VkDevice, descLayout: c.VkDescriptorSetLayout, index: usize, renderType: RenderType) !std.ArrayList(ShaderObject) {
    var list = std.ArrayList(ShaderObject).init(alloc);
    const shaders = config.renderSeq[index].shaders;

    for (0..shaders.len) |i| {
        const shader = shaders[i];
        const nextStage = if (i + 1 <= shaders.len - 1) shaders[i + 1].stage else 0;
        const shaderObj = try ShaderObject.init(gpi, shader, nextStage, alloc, descLayout, renderType);
        list.append(shaderObj) catch |err| {
            list.deinit();
            std.debug.print("ShaderManager could not append ShaderObject, err {}\n", .{err});
            return error.ShaderAppend;
        };
    }
    return list;
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
