const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const check = @import("error.zig").check;

pub const GraphicsShaderObject = struct {
    vertexShader: ?ShaderObject = null,
    fragmentShader: ?ShaderObject = null,
    meshShader: ?ShaderObject = null,
    taskShader: ?ShaderObject = null,
    descLayout: c.VkDescriptorSetLayout,

    pub fn deinit(self: GraphicsShaderObject, gpi: c.VkDevice) void {
        if (self.vertexShader) |shader| shader.deinit(gpi);
        if (self.fragmentShader) |shader| shader.deinit(gpi);
        if (self.meshShader) |shader| shader.deinit(gpi);
        if (self.taskShader) |shader| shader.deinit(gpi);
    }
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
            flags |= c.VK_SHADER_CREATE_NO_TASK_SHADER_BIT_EXT; // no task shader flag
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

pub const ShaderPipeline = struct {
    alloc: Allocator,
    layout: c.VkPipelineLayout,
    pipeType: PipelineType,
    shaderInfos: []const PipelineInfo,
    computeShaderObject: ?ShaderObject = null, // For compute
    graphicsShaderObject: ?GraphicsShaderObject = null, // For graphics/mesh

    pub fn init(alloc: Allocator, gpi: c.VkDevice, shaderInfos: []const PipelineInfo, descriptorLayout: c.VkDescriptorSetLayout, pipeType: PipelineType) !ShaderPipeline {
        switch (pipeType) {
            .compute => {
                if (shaderInfos.len > 1) std.log.err("Compute only supports one Stage in ShaderInfos\n", .{});
                const shaderInfo = shaderInfos[0];
                const shaderObj = try ShaderObject.init(gpi, shaderInfo.stage, shaderInfo.sprvPath, alloc, descriptorLayout, .compute);
                const layout = try createPipelineLayout(gpi, descriptorLayout, c.VK_SHADER_STAGE_COMPUTE_BIT, @sizeOf(ComputePushConstants));

                return .{
                    .alloc = alloc,
                    .layout = layout,
                    .pipeType = .compute,
                    .shaderInfos = shaderInfos,
                    .computeShaderObject = shaderObj,
                };
            },
            else => {
                var graphicsShaderObj = GraphicsShaderObject{ .descLayout = descriptorLayout };
                const layout = try createPipelineLayout(gpi, descriptorLayout, 0, 0); // No push constants
                // Create shaders based on pipeline type and shader infos
                for (shaderInfos) |shaderInfo| {
                    const shader = try ShaderObject.init(gpi, shaderInfo.stage, shaderInfo.sprvPath, alloc, descriptorLayout, pipeType);

                    switch (shaderInfo.stage) {
                        c.VK_SHADER_STAGE_VERTEX_BIT => graphicsShaderObj.vertexShader = shader,
                        c.VK_SHADER_STAGE_FRAGMENT_BIT => graphicsShaderObj.fragmentShader = shader,
                        c.VK_SHADER_STAGE_MESH_BIT_EXT => graphicsShaderObj.meshShader = shader,
                        c.VK_SHADER_STAGE_TASK_BIT_EXT => graphicsShaderObj.taskShader = shader,
                        else => return error.UnsupportedShaderStage,
                    }
                }

                return .{
                    .alloc = alloc,
                    .layout = layout,
                    .pipeType = pipeType,
                    .shaderInfos = shaderInfos,
                    .graphicsShaderObject = graphicsShaderObj,
                };
            },
        }
    }

    pub fn deinit(self: *ShaderPipeline, gpi: c.VkDevice) void {
        if (self.computeShaderObject) |shaderObj| {
            shaderObj.deinit(gpi);
            c.vkDestroyPipelineLayout(gpi, self.layout, null);
        } else if (self.graphicsShaderObject) |graphicsShaderObj| {
            graphicsShaderObj.deinit(gpi);
            c.vkDestroyPipelineLayout(gpi, self.layout, null);
        } else {
            c.vkDestroyPipelineLayout(gpi, self.layout, null);
        }
    }

    pub fn update(self: *ShaderPipeline, gpi: c.VkDevice, pipeType: PipelineType) !void {
        switch (pipeType) {
            .compute => {
                if (self.computeShaderObject) |*shaderObj| {
                    std.debug.print("sprv {s} \n", .{self.shaderInfos[0].sprvPath});
                    const layout = shaderObj.descLayout;
                    shaderObj.deinit(gpi);
                    self.computeShaderObject = try ShaderObject.init(gpi, self.shaderInfos[0].stage, self.shaderInfos[0].sprvPath, self.alloc, layout, .compute);
                    std.debug.print("Shader object {s} updated\n", .{@tagName(self.pipeType)});
                }
            },
            else => {
                if (self.graphicsShaderObject) |*graphicsShaderObj| {
                    // Recreate each shader
                    for (self.shaderInfos) |shaderInfo| {
                        const newShader = try ShaderObject.init(gpi, shaderInfo.stage, shaderInfo.sprvPath, self.alloc, graphicsShaderObj.descLayout, self.pipeType);

                        switch (shaderInfo.stage) {
                            c.VK_SHADER_STAGE_VERTEX_BIT => {
                                if (graphicsShaderObj.vertexShader) |old| old.deinit(gpi);
                                graphicsShaderObj.vertexShader = newShader;
                            },
                            c.VK_SHADER_STAGE_FRAGMENT_BIT => {
                                if (graphicsShaderObj.fragmentShader) |old| old.deinit(gpi);
                                graphicsShaderObj.fragmentShader = newShader;
                            },
                            c.VK_SHADER_STAGE_MESH_BIT_EXT => {
                                if (graphicsShaderObj.meshShader) |old| old.deinit(gpi);
                                graphicsShaderObj.meshShader = newShader;
                            },
                            c.VK_SHADER_STAGE_TASK_BIT_EXT => {
                                if (graphicsShaderObj.taskShader) |old| old.deinit(gpi);
                                graphicsShaderObj.taskShader = newShader;
                            },
                            else => return error.UnsupportedShaderStage,
                        }
                    }
                    std.debug.print("Graphics shader objects {s} updated\n", .{@tagName(self.pipeType)});
                }
            },
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
