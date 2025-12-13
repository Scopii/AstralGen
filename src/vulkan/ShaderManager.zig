const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const Context = @import("Context.zig").Context;
const RenderType = @import("../config.zig").RenderType;
const ShaderLayout = @import("../config.zig").ShaderLayout;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const check = @import("error.zig").check;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const ShaderStage = @import("ShaderObject.zig").ShaderStage;
const ztracy = @import("ztracy");

pub const PushConstants = extern struct {
    camPosAndFov: [4]f32,
    camDir: [4]f32,
    runtime: f32,
    dataCount: u32,
    renderImgIndex: u32,
};

pub const ShaderManager = struct {
    const seqLen = config.renderSeq.len;

    alloc: Allocator,
    descLayout: c.VkDescriptorSetLayout,
    pipeLayout: c.VkPipelineLayout,
    shaderObjects: [seqLen]std.ArrayList(ShaderObject),
    renderTypes: [seqLen]RenderType,
    gpi: c.VkDevice,

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !ShaderManager {
        const gpi = context.gpi;
        const pipeLayout = try createPipelineLayout(gpi, resourceManager.descLayout, c.VK_SHADER_STAGE_ALL, @sizeOf(PushConstants));

        var shaderObjects: [seqLen]std.ArrayList(ShaderObject) = undefined;
        for (0..seqLen) |i| shaderObjects[i] = std.ArrayList(ShaderObject).init(alloc);

        errdefer {
            for (0..seqLen) |i| {
                for (shaderObjects[i].items) |*shaderObj| shaderObj.deinit(gpi);
                shaderObjects[i].deinit();
            }
            c.vkDestroyPipelineLayout(gpi, pipeLayout, null);
        }

        var renderTypes: [seqLen]RenderType = undefined;
        for (0..seqLen) |i| {
            const renderPass = config.renderSeq[i];
            renderTypes[i] = try checkShaderLayout(renderPass);
            std.debug.print("ShaderLayout {} renderType {s} for RenderId {} valid\n", .{ i, @tagName(renderTypes[i]), renderPass.renderImg.id });
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

    pub fn updateShaderLayout(self: *ShaderManager, seqIndex: usize) !void {
        const renderPass = config.renderSeq[seqIndex];
        const renderType = try checkShaderLayout(renderPass);
        std.debug.print("ShaderLayout {} renderType {s} for RenderId {} updated\n", .{ seqIndex, @tagName(renderType), renderPass.renderImg.id });

        const newList = try setShaderLayout(self.alloc, self.gpi, self.descLayout, seqIndex, renderType);

        const listPtr = &self.shaderObjects[seqIndex];
        for (listPtr.items) |*shaderObject| shaderObject.deinit(self.gpi);
        listPtr.deinit();
        listPtr.* = newList;

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
    var shdr: [8]u8 = .{0} ** 8;
    var prevIndex: i8 = -1;

    for (shaderLayout.shaders) |shader| {
        const curIndex: i8 = switch (shader.stage) {
            .compute => 0,
            .vertex => 1,
            .tessControl => 2,
            .tessEval => 3,
            .geometry => 4,
            .task => 5,
            .mesh => 6,
            .frag => 7,
        };
        if (curIndex <= prevIndex) return error.ShaderLayoutOrderInvalid;
        prevIndex = curIndex;
        shdr[@intCast(curIndex)] += 1;
    }
    switch (shaderLayout.shaders.len) {
        1 => if (shdr[0] == 1) return .computePass else if (shdr[1] == 1) return .vertexPass,
        2 => if (shdr[6] == 1 and shdr[7] == 1) return .meshPass,
        3 => if (shdr[5] == 1 and shdr[6] == 1 and shdr[7] == 1) return .taskMeshPass,
        else => {},
    }
    if (shdr[1] == 1 and shdr[2] <= 1 and shdr[3] <= 1 and shdr[4] <= 1 and shdr[5] == 0 and shdr[6] == 0 and shdr[7] == 1) return .graphicsPass;
    if (shdr[2] != shdr[3]) return error.ShaderLayoutTessellationMismatch;
    return error.ShaderLayoutInvalid;
}

fn setShaderLayout(alloc: Allocator, gpi: c.VkDevice, descLayout: c.VkDescriptorSetLayout, index: usize, renderType: RenderType) !std.ArrayList(ShaderObject) {
    var list = std.ArrayList(ShaderObject).init(alloc);
    errdefer {
        for (list.items) |*so| so.deinit(gpi);
        list.deinit();
    }
    const shaders = config.renderSeq[index].shaders;

    for (0..shaders.len) |i| {
        const shader = shaders[i];
        const nextStage: c.VkShaderStageFlagBits = if (i + 1 <= shaders.len - 1) @intFromEnum(shaders[i + 1].stage) else 0;
        const shaderObj = try ShaderObject.init(alloc, gpi, shader, nextStage, descLayout, renderType);

        list.append(shaderObj) catch |err| {
            shaderObj.deinit(gpi);
            std.debug.print("ShaderManager could not append ShaderObject, err {}\n", .{err});
            return error.ShaderAppend; // triggers errdefer above
        };
    }
    return list;
}

fn createPipelineLayout(gpi: c.VkDevice, descLayout: c.VkDescriptorSetLayout, stageFlags: c.VkShaderStageFlags, size: u32) !c.VkPipelineLayout {
    const pcRange = c.VkPushConstantRange{ .stageFlags = stageFlags, .offset = 0, .size = size };
    const pipeLayoutInf = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = if (descLayout != null) 1 else 0,
        .pSetLayouts = if (descLayout != null) &descLayout else null,
        .pushConstantRangeCount = if (size > 0) 1 else 0,
        .pPushConstantRanges = if (size > 0) &pcRange else null,
    };
    var layout: c.VkPipelineLayout = undefined;
    try check(c.vkCreatePipelineLayout(gpi, &pipeLayoutInf, null, &layout), "Failed to create pipeline layout");
    return layout;
}
