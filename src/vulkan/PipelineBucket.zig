const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const check = @import("error.zig").check;

pub const GraphicsShaderObject = struct {
    vertexShader: ?ShaderObject = null,
    fragmentShader: ?ShaderObject = null,
    meshShader: ?ShaderObject = null,
    taskShader: ?ShaderObject = null, // Optional for mesh shaders
    descLayout: c.VkDescriptorSetLayout,

    pub fn deinit(self: GraphicsShaderObject, gpi: c.VkDevice) void {
        if (self.vertexShader) |shader| shader.deinit(gpi);
        if (self.fragmentShader) |shader| shader.deinit(gpi);
        if (self.meshShader) |shader| shader.deinit(gpi);
        if (self.taskShader) |shader| shader.deinit(gpi);
    }
};

pub const ShaderObject = struct {
    handle: c.VkShaderEXT,
    stage: c.VkShaderStageFlagBits,
    descLayout: c.VkDescriptorSetLayout,

    // New init function for graphics shaders
    pub fn initGraphics(gpi: c.VkDevice, stage: c.VkShaderStageFlagBits, spvPath: []const u8, alloc: Allocator, descriptorLayout: c.VkDescriptorSetLayout, pipeType: PipelineType) !ShaderObject {
        const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
        defer alloc.free(exe_dir);
        const runtimeSpvPath = try std.fs.path.join(alloc, &[_][]const u8{ exe_dir, "..", spvPath });
        defer alloc.free(runtimeSpvPath);

        const spvData = try loadShader(alloc, runtimeSpvPath);
        defer alloc.free(spvData);

        // Determine next stage for graphics pipeline
        var nextStage: c.VkShaderStageFlags = 0;
        if (stage == c.VK_SHADER_STAGE_VERTEX_BIT) {
            nextStage = c.VK_SHADER_STAGE_FRAGMENT_BIT;
        } else if (stage == c.VK_SHADER_STAGE_TASK_BIT_EXT) {
            nextStage = c.VK_SHADER_STAGE_MESH_BIT_EXT;
        } else if (stage == c.VK_SHADER_STAGE_MESH_BIT_EXT) {
            nextStage = c.VK_SHADER_STAGE_FRAGMENT_BIT;
        }

        // Set flags based on shader stage
        var flags: c.VkShaderCreateFlagsEXT = 0;
        if (stage == c.VK_SHADER_STAGE_MESH_BIT_EXT and pipeType == .mesh) {
            // If no task shader will be used, set this flag
            flags |= c.VK_SHADER_CREATE_NO_TASK_SHADER_BIT_EXT;
        }

        // Push constant setup based on pipeline type
        var pushConstantRange: c.VkPushConstantRange = undefined;
        var pushConstantRangeCount: u32 = 0;
        var pushConstantRanges: ?*const c.VkPushConstantRange = null;

        if (pipeType == .compute) {
            pushConstantRange = c.VkPushConstantRange{
                .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
                .offset = 0,
                .size = @sizeOf(ComputePushConstants),
            };
            pushConstantRangeCount = 1;
            pushConstantRanges = &pushConstantRange;
        }

        const shaderCreateInfo = c.VkShaderCreateInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .pNext = null,
            .flags = flags, // Use the flags we set
            .stage = stage,
            .nextStage = nextStage,
            .codeType = c.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = spvData.len,
            .pCode = spvData.ptr,
            .pName = "main",
            .setLayoutCount = if (descriptorLayout != null) @as(u32, 1) else 0,
            .pSetLayouts = if (descriptorLayout != null) &descriptorLayout else null,
            .pushConstantRangeCount = pushConstantRangeCount,
            .pPushConstantRanges = pushConstantRanges,
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

    pub fn init(gpi: c.VkDevice, stage: c.VkShaderStageFlagBits, spvPath: []const u8, alloc: Allocator, descriptorLayout: c.VkDescriptorSetLayout) !ShaderObject {
        const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
        defer alloc.free(exe_dir);
        // For runtime: look for shader folder next to exe (in parent of bin/)
        const runtimeSpvPath = try std.fs.path.join(alloc, &[_][]const u8{ exe_dir, "..", spvPath });
        defer alloc.free(runtimeSpvPath);

        const spvData = try loadShader(alloc, runtimeSpvPath);
        defer alloc.free(spvData);

        const shaderCreateInfo = c.VkShaderCreateInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .pNext = null,
            .flags = 0,
            .stage = stage,
            .nextStage = 0, // No next stage for compute
            .codeType = c.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = spvData.len,
            .pCode = spvData.ptr,
            .pName = "main",
            .setLayoutCount = 1, // Your compute shader uses 1 descriptor set
            .pSetLayouts = &descriptorLayout, // Will bind descriptor buffer instead
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &c.VkPushConstantRange{
                .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
                .offset = 0,
                .size = @sizeOf(ComputePushConstants),
            },
            .pSpecializationInfo = null,
        };

        var shader: c.VkShaderEXT = undefined;
        try check(c.pfn_vkCreateShadersEXT.?(gpi, 1, &shaderCreateInfo, null, &shader), "Failed to create shader object");

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

pub const Pipeline = struct {
    alloc: Allocator,
    handle: c.VkPipeline,
    layout: c.VkPipelineLayout,
    format: ?c.VkFormat,
    pipeType: PipelineType,
    shaderInfos: []const PipelineInfo,
    shaderObject: ?ShaderObject = null, // For compute
    graphicsShaderObject: ?GraphicsShaderObject = null, // For graphics/mesh

    pub fn initShaderObject(alloc: Allocator, gpi: c.VkDevice, shaderInfos: []const PipelineInfo, descriptorLayout: c.VkDescriptorSetLayout) !Pipeline {
        const shaderInfo = shaderInfos[0];
        const shaderObj = try ShaderObject.init(gpi, shaderInfo.stage, shaderInfo.sprvPath, alloc, descriptorLayout);

        const pushConstantRange = c.VkPushConstantRange{
            .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
            .offset = 0,
            .size = @sizeOf(ComputePushConstants),
        };

        const pipeLayoutInf = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 1,
            .pSetLayouts = &descriptorLayout,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &pushConstantRange,
        };
        var pipelineLayout: c.VkPipelineLayout = undefined;
        try check(c.vkCreatePipelineLayout(gpi, &pipeLayoutInf, null, &pipelineLayout), "Failed to create pipeline layout for shader object");

        return .{
            .alloc = alloc,
            .handle = undefined, // Not used with shader objects
            .layout = pipelineLayout,
            .format = null,
            .pipeType = .compute,
            .shaderInfos = shaderInfos, // Store for hot reload
            .shaderObject = shaderObj,
        };
    }

    // New init function for graphics shader objects
    pub fn initGraphicsShaderObject(alloc: Allocator, gpi: c.VkDevice, shaderInfos: []const PipelineInfo, descriptorLayout: c.VkDescriptorSetLayout, pipeType: PipelineType) !Pipeline {
        var graphicsShaderObj = GraphicsShaderObject{ .descLayout = descriptorLayout };

        // Create shaders based on pipeline type and shader infos
        for (shaderInfos) |shaderInfo| {
            const shader = try ShaderObject.initGraphics(gpi, shaderInfo.stage, shaderInfo.sprvPath, alloc, descriptorLayout, pipeType);

            switch (shaderInfo.stage) {
                c.VK_SHADER_STAGE_VERTEX_BIT => graphicsShaderObj.vertexShader = shader,
                c.VK_SHADER_STAGE_FRAGMENT_BIT => graphicsShaderObj.fragmentShader = shader,
                c.VK_SHADER_STAGE_MESH_BIT_EXT => graphicsShaderObj.meshShader = shader,
                c.VK_SHADER_STAGE_TASK_BIT_EXT => graphicsShaderObj.taskShader = shader,
                else => return error.UnsupportedShaderStage,
            }
        }

        const layout = try createGraphicsPipelineLayout(gpi, descriptorLayout);

        return .{
            .alloc = alloc,
            .handle = undefined, // Not used with shader objects
            .layout = layout,
            .format = null,
            .pipeType = pipeType,
            .shaderInfos = shaderInfos,
            .graphicsShaderObject = graphicsShaderObj,
        };
    }

    pub fn deinit(self: *Pipeline, gpi: c.VkDevice) void {
        if (self.shaderObject) |shaderObj| {
            shaderObj.deinit(gpi);
            c.vkDestroyPipelineLayout(gpi, self.layout, null);
        } else if (self.graphicsShaderObject) |graphicsShaderObj| {
            graphicsShaderObj.deinit(gpi);
            c.vkDestroyPipelineLayout(gpi, self.layout, null);
        } else {
            c.vkDestroyPipeline(gpi, self.handle, null);
            c.vkDestroyPipelineLayout(gpi, self.layout, null);
        }
    }

    pub fn updateShaderObject(self: *Pipeline, gpi: c.VkDevice) !void {
        if (self.shaderObject) |*shaderObj| {
            std.debug.print("sprv {s} \n", .{self.shaderInfos[0].sprvPath});
            const layout = shaderObj.descLayout;
            shaderObj.deinit(gpi);
            self.shaderObject = try ShaderObject.init(gpi, self.shaderInfos[0].stage, self.shaderInfos[0].sprvPath, self.alloc, layout);
            std.debug.print("Shader object {s} updated\n", .{@tagName(self.pipeType)});
        }
    }

    // Update graphics shader objects for hot reload
    pub fn updateGraphicsShaderObject(self: *Pipeline, gpi: c.VkDevice) !void {
        if (self.graphicsShaderObject) |*graphicsShaderObj| {
            // Recreate each shader
            for (self.shaderInfos) |shaderInfo| {
                const newShader = try ShaderObject.initGraphics(gpi, shaderInfo.stage, shaderInfo.sprvPath, self.alloc, graphicsShaderObj.descLayout, self.pipeType);

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
    }
};

fn createGraphicsPipelineLayout(gpi: c.VkDevice, descSetLayout: c.VkDescriptorSetLayout) !c.VkPipelineLayout {
    // Graphics pipelines typically don't need push constants like compute
    const pipeLayoutInf = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = if (descSetLayout != null) @as(u32, 1) else 0,
        .pSetLayouts = if (descSetLayout != null) &descSetLayout else null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };
    var layout: c.VkPipelineLayout = undefined;
    try check(c.vkCreatePipelineLayout(gpi, &pipeLayoutInf, null, &layout), "Failed to create graphics pipeline layout");
    return layout;
}

pub const ComputePushConstants = extern struct {
    camPosAndFov: [4]f32,
    camDir: [4]f32,
    runtime: f32,
    dataCount: u32,
    dataAddress: u64,
};

fn createPipelineLayout(gpi: c.VkDevice, descSetLayout: c.VkDescriptorSetLayout, layoutCount: u32) !c.VkPipelineLayout {
    const pushConstantRange = c.VkPushConstantRange{
        .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
        .offset = 0,
        .size = @sizeOf(ComputePushConstants), // Updated size for buffer addresses
    };
    const pipeLayoutInf = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = layoutCount,
        .pSetLayouts = if (layoutCount > 0) &descSetLayout else null,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &pushConstantRange,
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

pub fn createShaderModule(alloc: std.mem.Allocator, spvPath: []const u8, gpi: c.VkDevice) !c.VkShaderModule {
    const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exe_dir);
    // For runtime: look for shader folder next to exe (in parent of bin/)
    const runtimeSpvPath = try std.fs.path.join(alloc, &[_][]const u8{ exe_dir, "..", spvPath });
    defer alloc.free(runtimeSpvPath);

    if (config.SHADER_HOTLOAD) {
        // For development: resolve source path from project root
        const projectRoot = try std.fs.path.resolve(alloc, &[_][]const u8{ exe_dir, config.rootPath });
        defer alloc.free(projectRoot);
        // Create output directory if needed
        if (std.fs.path.dirname(runtimeSpvPath)) |dir_path| {
            std.fs.cwd().makePath(dir_path) catch {}; // Ignore if exists
        }
    }
    // Load compiled shader (works for both hotload and pre-compiled)
    const loadedShader = try loadShader(alloc, runtimeSpvPath);
    defer alloc.free(loadedShader);

    const createInf = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = loadedShader.len,
        .pCode = @ptrCast(@alignCast(loadedShader.ptr)),
    };
    var shdrMod: c.VkShaderModule = undefined;
    try check(c.vkCreateShaderModule(gpi, &createInf, null, &shdrMod), "Failed to create shader module");
    return shdrMod;
}
