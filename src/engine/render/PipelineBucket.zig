const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("../error.zig").check;
const createShaderModule = @import("../../shader/shader.zig").createShaderModule;

pub const ShaderInfo = struct {
    stage: c.VkShaderStageFlagBits,
    inputPath: []const u8,
    outputPath: []const u8,
};

pub const PipelineType = enum { compute, graphics, mesh };

pub const PipelineBucket = struct {
    alloc: Allocator,
    handle: c.VkPipeline,
    layout: c.VkPipelineLayout,
    format: ?c.VkFormat,
    timeStamp: u64,
    pipelineType: PipelineType,
    shaderInfos: []const ShaderInfo,

    pub fn init(
        alloc: Allocator,
        gpi: c.VkDevice,
        cache: c.VkPipelineCache,
        format: c.VkFormat,
        shaderInfos: []const ShaderInfo,
        pipelineType: PipelineType,
        descriptorLayout: c.VkDescriptorSetLayout,
        layoutCount: u32,
    ) !PipelineBucket {
        const modules = try createShaderModules(alloc, gpi, shaderInfos);
        defer {
            for (0..modules.len) |i| {
                c.vkDestroyShaderModule(gpi, modules[i], null);
            }
            alloc.free(modules);
        }
        const stages = try createShaderStages(alloc, modules, shaderInfos);
        defer alloc.free(stages);

        var timeStamp: u64 = 0;
        for (0..shaderInfos.len) |i| {
            const tempTimeStamp = try getFileTimeStamp(alloc, shaderInfos[i].inputPath);
            if (tempTimeStamp > timeStamp) timeStamp = tempTimeStamp;
        }

        const layout = try createPipelineLayout(gpi, descriptorLayout, layoutCount);
        const pipeline = try createPipeline(gpi, layout, stages, cache, pipelineType, format);

        return .{
            .alloc = alloc,
            .handle = pipeline,
            .layout = layout,
            .format = format,
            .timeStamp = timeStamp,
            .pipelineType = pipelineType,
            .shaderInfos = shaderInfos,
        };
    }

    pub fn deinit(self: *PipelineBucket, gpi: c.VkDevice) void {
        c.vkDestroyPipeline(gpi, self.handle, null);
        c.vkDestroyPipelineLayout(gpi, self.layout, null);
    }

    pub fn checkUpdate(self: *PipelineBucket, gpi: c.VkDevice, cache: c.VkPipelineCache) !void {
        const alloc = self.alloc;
        var timeStamp: u64 = 0;
        var pathIndex: u64 = 0;
        for (0..self.shaderInfos.len) |i| {
            const tempTimeStamp = try getFileTimeStamp(alloc, self.shaderInfos[i].inputPath);
            if (tempTimeStamp > timeStamp) {
                timeStamp = tempTimeStamp;
                pathIndex = i;
            }
        }
        if (timeStamp == self.timeStamp) return;

        self.timeStamp = timeStamp;
        _ = c.vkDeviceWaitIdle(gpi);

        c.vkDestroyPipeline(gpi, self.handle, null);
        const modules = try createShaderModules(alloc, gpi, self.shaderInfos);
        defer {
            for (0..modules.len) |i| {
                c.vkDestroyShaderModule(gpi, modules[i], null);
            }
            alloc.free(modules);
        }
        const stages = try createShaderStages(alloc, modules, self.shaderInfos);
        defer alloc.free(stages);
        self.handle = try createPipeline(gpi, self.layout, stages, cache, self.pipelineType, self.format);
        std.debug.print("{s} at {s} updated\n", .{ @tagName(self.pipelineType), self.shaderInfos[pathIndex].inputPath });
    }
};

fn createShaderStage(stage: u32, module: c.VkShaderModule, name: [*]const u8) c.VkPipelineShaderStageCreateInfo {
    return c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = stage, //
        .module = module,
        .pName = name,
        .pSpecializationInfo = null, // for constants
    };
}

fn createShaderStages(alloc: Allocator, modules: []c.VkShaderModule, shaderInf: []const ShaderInfo) ![]c.VkPipelineShaderStageCreateInfo {
    var stages = try alloc.alloc(c.VkPipelineShaderStageCreateInfo, shaderInf.len);
    errdefer alloc.free(stages);
    for (0..shaderInf.len) |i| {
        stages[i] = createShaderStage(shaderInf[i].stage, modules[i], "main");
    }
    return stages;
}

fn createShaderModules(alloc: Allocator, gpi: c.VkDevice, shaderInf: []const ShaderInfo) ![]c.VkShaderModule {
    var modules = try alloc.alloc(c.VkShaderModule, shaderInf.len);
    errdefer alloc.free(modules);
    for (0..shaderInf.len) |i| {
        modules[i] = try createShaderModule(alloc, shaderInf[i].inputPath, shaderInf[i].outputPath, gpi);
    }
    return modules;
}

fn createPipelineLayout(gpi: c.VkDevice, descriptorSetLayout: c.VkDescriptorSetLayout, layoutCount: u32) !c.VkPipelineLayout {
    const pipeLayoutInf = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = layoutCount,
        .pSetLayouts = &descriptorSetLayout,
        .pushConstantRangeCount = 0,
    };
    var layout: c.VkPipelineLayout = undefined;
    try check(c.vkCreatePipelineLayout(gpi, &pipeLayoutInf, null, &layout), "Failed to create pipeline layout");
    return layout;
}

fn createPipeline(
    gpi: c.VkDevice,
    layout: c.VkPipelineLayout,
    shaderStages: []const c.VkPipelineShaderStageCreateInfo,
    cache: c.VkPipelineCache,
    pipelineType: PipelineType,
    format: ?c.VkFormat,
) !c.VkPipeline {
    switch (pipelineType) {
        .compute => {
            if (shaderStages.len > 1) return error.ComputeCantHaveMultipleStages;

            const pipeInf = c.VkComputePipelineCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
                .stage = shaderStages[0],
                .layout = layout,
            };

            var pipe: c.VkPipeline = undefined;
            try check(c.vkCreateComputePipelines(gpi, cache, 1, &pipeInf, null, &pipe), "Failed to create pipeline");
            return pipe;
        },
        .graphics, .mesh => {
            const viewInf = c.VkPipelineViewportStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                .viewportCount = 1,
                .scissorCount = 1,
            };

            const rasterInf = c.VkPipelineRasterizationStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                .depthClampEnable = c.VK_FALSE,
                .rasterizerDiscardEnable = c.VK_FALSE,
                .polygonMode = c.VK_POLYGON_MODE_FILL,
                .cullMode = c.VK_CULL_MODE_NONE, // VK_CULL_MODE_BACK_BIT
                .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
                .depthBiasEnable = c.VK_FALSE,
                .depthBiasConstantFactor = 0.0,
                .depthBiasClamp = 0.0,
                .depthBiasSlopeFactor = 0.0,
                .lineWidth = 1.0,
            };

            const msaaInf = c.VkPipelineMultisampleStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                .flags = 0,
                .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
                .sampleShadingEnable = c.VK_FALSE,
                .minSampleShading = 1.0,
                .pSampleMask = null,
                .alphaToCoverageEnable = c.VK_FALSE,
                .alphaToOneEnable = c.VK_FALSE,
            };

            const colBlendAttach = c.VkPipelineColorBlendAttachmentState{
                .blendEnable = c.VK_FALSE,
                .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
                .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                .colorBlendOp = c.VK_BLEND_OP_ADD,
                .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
                .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                .alphaBlendOp = c.VK_BLEND_OP_ADD,
                .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT |
                    c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
            };

            const colBlendInf = c.VkPipelineColorBlendStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                .logicOpEnable = c.VK_FALSE,
                .logicOp = c.VK_LOGIC_OP_COPY,
                .attachmentCount = 1,
                .pAttachments = &colBlendAttach,
                .blendConstants = [4]f32{ 0.0, 0.0, 0.0, 0.0 },
            };

            const dynStates = [_]c.VkDynamicState{
                c.VK_DYNAMIC_STATE_VIEWPORT,
                c.VK_DYNAMIC_STATE_SCISSOR,
            };

            const dynStateInf = c.VkPipelineDynamicStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                .dynamicStateCount = dynStates.len,
                .pDynamicStates = &dynStates,
            };

            if (format == null) return error.PipelineNeedsFormat;
            const checkedFormat = format.?; // Unwrap the optional to get the value.

            const colFormats = [_]c.VkFormat{checkedFormat};
            var pipeline_rendering_info = c.VkPipelineRenderingCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
                .viewMask = 0,
                .colorAttachmentCount = 1,
                .pColorAttachmentFormats = &colFormats,
                .depthAttachmentFormat = c.VK_FORMAT_UNDEFINED,
                .stencilAttachmentFormat = c.VK_FORMAT_UNDEFINED,
            };

            if (pipelineType == .mesh) {
                const pipelineInf = c.VkGraphicsPipelineCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
                    .pNext = &pipeline_rendering_info,
                    .stageCount = @intCast(shaderStages.len),
                    .pStages = shaderStages.ptr,
                    // Mesh shaders don't use Vertex Input or Input Assembly states.
                    .pVertexInputState = null,
                    .pInputAssemblyState = null,
                    .pViewportState = &viewInf,
                    .pRasterizationState = &rasterInf,
                    .pMultisampleState = &msaaInf,
                    .pDepthStencilState = null,
                    .pColorBlendState = &colBlendInf,
                    .pDynamicState = &dynStateInf,
                    .layout = layout,
                    .subpass = 0,
                    .basePipelineIndex = -1,
                };
                var pipe: c.VkPipeline = undefined;
                try check(c.vkCreateGraphicsPipelines(gpi, cache, 1, &pipelineInf, null, &pipe), "Failed to create Mesh Pipeline");
                return pipe;
            } else {
                const vertInputInf = c.VkPipelineVertexInputStateCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                    .vertexBindingDescriptionCount = 0,
                    .vertexAttributeDescriptionCount = 0,
                };

                const assemblyInf = c.VkPipelineInputAssemblyStateCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                    .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, // triangle from every 3 vertices without reuse
                    // VK_PRIMITIVE_TOPOLOGY_POINT_LIST         points from vertices
                    // VK_PRIMITIVE_TOPOLOGY_LINE_LIST          line from every 2 vertices without reuse
                    // VK_PRIMITIVE_TOPOLOGY_LINE_STRIP         end vertex of every line is used as start vertex for next line
                    // VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP     second and third vertex of every triangle are used as first two vertices of the next triangle
                    .primitiveRestartEnable = c.VK_FALSE,
                };

                const pipelineInf = c.VkGraphicsPipelineCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
                    .pNext = &pipeline_rendering_info,
                    .stageCount = @intCast(shaderStages.len),
                    .pStages = shaderStages.ptr,
                    .pVertexInputState = &vertInputInf,
                    .pInputAssemblyState = &assemblyInf,
                    .pViewportState = &viewInf,
                    .pRasterizationState = &rasterInf,
                    .pMultisampleState = &msaaInf,
                    .pDepthStencilState = null,
                    .pColorBlendState = &colBlendInf,
                    .pDynamicState = &dynStateInf,
                    .layout = layout,
                    .subpass = 0,
                    .basePipelineIndex = -1,
                };
                var pipe: c.VkPipeline = undefined;
                try check(c.vkCreateGraphicsPipelines(gpi, cache, 1, &pipelineInf, null, &pipe), "Failed to create Graphics Pipeline");
                return pipe;
            }
        },
    }
}

pub fn getFileTimeStamp(alloc: Allocator, src: []const u8) !u64 {
    const abs_path = try resolveAssetPath(alloc, src);
    defer alloc.free(abs_path);

    const cwd = std.fs.cwd();
    const stat = try cwd.statFile(abs_path);
    const ns: u64 = @intCast(stat.mtime); // cast before division
    return ns / 1_000_000; // convert nanoseconds to milliseconds
}

pub fn resolveAssetPath(alloc: Allocator, asset_path: []const u8) ![]u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exe_dir);

    // Project root (up two levels from zig-out/bin)
    const project_root = try std.fs.path.resolve(alloc, &[_][]const u8{ exe_dir, "..", ".." });
    defer alloc.free(project_root);

    return std.fs.path.join(alloc, &[_][]const u8{ project_root, asset_path });
}
