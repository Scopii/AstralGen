const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const Context = @import("Context.zig").Context;
const RenderType = @import("../config.zig").RenderType;
const ShaderLayout = @import("../config.zig").ShaderLayout;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const LoadedShader = @import("../core/ShaderCompiler.zig").LoadedShader;
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
    padding: u32 = 0,
    viewProj: [4][4]f32,
};

pub const ShaderManager = struct {
    alloc: Allocator,
    descLayout: c.VkDescriptorSetLayout,
    pipeLayout: c.VkPipelineLayout,
    gpi: c.VkDevice,
    shaders: CreateMapArray(ShaderObject, config.SHADER_MAX, u32, config.SHADER_MAX, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !ShaderManager {
        const gpi = context.gpi;
        const pipeLayout = try createPipelineLayout(gpi, resourceManager.descLayout, c.VK_SHADER_STAGE_ALL, @sizeOf(PushConstants));

        return .{
            .alloc = alloc,
            .descLayout = resourceManager.descLayout,
            .pipeLayout = pipeLayout,
            .gpi = gpi,
        };
    }

    pub fn createShaders(self: *ShaderManager, loadedShaders: []LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            const shaderObj = try ShaderObject.init(self.gpi, loadedShader, self.descLayout);
            self.shaders.set(loadedShader.id, shaderObj);
        }
    }

    pub fn getShaders(self: *ShaderManager, shaderIds: []const u8) [8]ShaderObject {
        var shaders: [8]ShaderObject = undefined;
        for (0..shaderIds.len) |i| {
            shaders[i] = self.shaders.get(shaderIds[i]);
        }
        return shaders;
    }

    pub fn deinit(self: *ShaderManager) void {
        const gpi = self.gpi;
        for (self.shaders.getElements()) |*shader| {
            shader.deinit(self.gpi);
        }
        c.vkDestroyPipelineLayout(gpi, self.pipeLayout, null);
    }
};

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
