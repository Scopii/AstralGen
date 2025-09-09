const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const check = @import("error.zig").check;

pub const PipelineType = enum { compute, graphics, mesh };

pub const ShaderInfo = struct {
    pipeType: PipelineType,
    inputName: []const u8,
    outputName: []const u8,
};

pub const PipelineInfo = struct {
    pipeType: PipelineType,
    stage: c.VkShaderStageFlagBits,
    sprvPath: []const u8,
};

pub const ComputePushConstants = extern struct {
    camPosAndFov: [4]f32,
    camDir: [4]f32,
    runtime: f32,
    dataCount: u32,
    dataAddress: u64,
};

pub const ShaderObject = struct {
    handle: c.VkShaderEXT,
    stage: c.VkShaderStageFlagBits,
    descLayout: c.VkDescriptorSetLayout,

    pub fn init(
        gpi: c.VkDevice,
        stage: c.VkShaderStageFlagBits,
        spvPath: []const u8,
        alloc: Allocator,
        descriptorLayout: c.VkDescriptorSetLayout,
        pipeType: PipelineType,
    ) !ShaderObject {
        const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
        defer alloc.free(exe_dir);
        const runtimeSpvPath = try std.fs.path.join(alloc, &[_][]const u8{ exe_dir, "..", spvPath });
        defer alloc.free(runtimeSpvPath);

        const spvData = try loadShader(alloc, runtimeSpvPath);
        defer alloc.free(spvData);

        // Determine next stage for graphics pipeline
        const nextStage: c.VkShaderStageFlags = switch (stage) {
            c.VK_SHADER_STAGE_COMPUTE_BIT => 0,
            c.VK_SHADER_STAGE_VERTEX_BIT => c.VK_SHADER_STAGE_FRAGMENT_BIT,
            c.VK_SHADER_STAGE_TASK_BIT_EXT => c.VK_SHADER_STAGE_MESH_BIT_EXT,
            c.VK_SHADER_STAGE_MESH_BIT_EXT => c.VK_SHADER_STAGE_FRAGMENT_BIT,
            else => 0,
        };

        // Set flags based on shader stage
        var flags: c.VkShaderCreateFlagsEXT = 0;
        if (stage == c.VK_SHADER_STAGE_MESH_BIT_EXT and pipeType == .mesh) {
            flags |= c.VK_SHADER_CREATE_NO_TASK_SHADER_BIT_EXT; // because task shader isnt used YET
        }

        const shaderCreateInfo = c.VkShaderCreateInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .pNext = null,
            .flags = if (pipeType == .compute) 0 else flags,
            .stage = stage,
            .nextStage = nextStage,
            .codeType = c.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = spvData.len,
            .pCode = spvData.ptr,
            .pName = "main",
            .setLayoutCount = if (descriptorLayout != null) @as(u32, 1) else 0,
            .pSetLayouts = if (descriptorLayout != null) &descriptorLayout else null,
            .pushConstantRangeCount = if (pipeType == .compute) 1 else 0,
            .pPushConstantRanges = if (pipeType == .compute) &c.VkPushConstantRange{
                .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
                .offset = 0,
                .size = @sizeOf(ComputePushConstants),
            } else null,
            .pSpecializationInfo = null,
        };

        var shader: c.VkShaderEXT = undefined;
        try check(c.pfn_vkCreateShadersEXT.?(gpi, 1, &shaderCreateInfo, null, &shader), "Failed to create graphics shader object");

        return .{
            .handle = shader,
            .stage = stage,
            .descLayout = descriptorLayout,
        };
    }

    pub fn deinit(self: ShaderObject, gpi: c.VkDevice) void {
        c.pfn_vkDestroyShaderEXT.?(gpi, self.handle, null);
    }
};

pub const ShaderPipeline = struct {
    alloc: Allocator,
    layout: c.VkPipelineLayout,
    pipeType: PipelineType,
    shaderInfos: []const PipelineInfo,
    descLayout: c.VkDescriptorSetLayout,
    shaderObjects: std.ArrayList(ShaderObject),

    pub fn init(alloc: Allocator, gpi: c.VkDevice, pipeInfos: []const PipelineInfo, descriptorLayout: c.VkDescriptorSetLayout, pipeType: PipelineType) !ShaderPipeline {
        var shaderObjects = std.ArrayList(ShaderObject).init(alloc);
        if (pipeType == .compute and pipeInfos.len > 1) {
            std.log.err("ShaderPipeline: Compute only supports 1 Stage", .{});
            return error.ShaderStageOverflow;
        }

        const layout = switch (pipeType) {
            .compute => try createPipelineLayout(gpi, descriptorLayout, pipeInfos[0].stage, @sizeOf(ComputePushConstants)),
            else => try createPipelineLayout(gpi, descriptorLayout, 0, 0),
        };

        for (pipeInfos) |pipeInfo| {
            const shaderObj = try ShaderObject.init(gpi, pipeInfo.stage, pipeInfo.sprvPath, alloc, descriptorLayout, pipeType);
            shaderObjects.append(shaderObj) catch |err| {
                std.debug.print("PipelineBucket: Could not append ShaderObject, err {}\n", .{err});
            };
        }

        return .{
            .alloc = alloc,
            .layout = layout,
            .pipeType = pipeType,
            .shaderInfos = pipeInfos,
            .shaderObjects = shaderObjects,
            .descLayout = descriptorLayout,
        };
    }

    pub fn deinit(self: *ShaderPipeline, gpi: c.VkDevice) void {
        for (self.shaderObjects.items) |*shaderObject| {
            shaderObject.deinit(gpi);
        }
        c.vkDestroyPipelineLayout(gpi, self.layout, null);
        self.shaderObjects.deinit();
    }

    pub fn update(self: *ShaderPipeline, gpi: c.VkDevice, pipeType: PipelineType) !void {
        for (self.shaderObjects.items) |*shaderObject| {
            shaderObject.deinit(gpi);
        }
        self.shaderObjects.clearRetainingCapacity();
        for (self.shaderInfos) |shaderInfo| {
            const shaderObj = try ShaderObject.init(gpi, shaderInfo.stage, shaderInfo.sprvPath, self.alloc, self.descLayout, pipeType);

            self.shaderObjects.append(shaderObj) catch |err| {
                std.debug.print("PipelineBucket: Could not append ShaderObject, err {}\n", .{err});
            };
        }
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

fn loadShader(alloc: Allocator, spvPath: []const u8) ![]align(@alignOf(u32)) u8 {
    std.debug.print("Loading shader: {s}\n", .{spvPath});
    const file = std.fs.cwd().openFile(spvPath, .{}) catch |err| {
        std.debug.print("Failed to load shader: {s}\n", .{spvPath});
        return err;
    };
    defer file.close();

    const size = try file.getEndPos();
    const data = try alloc.alignedAlloc(u8, @alignOf(u32), size);
    _ = try file.readAll(data);
    return data;
}
