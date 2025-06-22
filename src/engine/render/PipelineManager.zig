const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("../error.zig").check;
const createShaderModule = @import("../../shader/shader.zig").createShaderModule;
const ztracy = @import("ztracy");
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const Context = @import("Context.zig").Context;

const computeInputPath = "src/shader/shdr.comp";
const computeOutputPath = "zig-out/shader/comp.spv";

const graphicsVertPath = "src/shader/shdr.vert";
const graphicsVertOutputPath = "zig-out/shader/vert.spv";
const graphicsFragPath = "src/shader/shdr.frag";
const graphicsFragOutputPath = "zig-out/shader/frag.spv";

const meshInputPath = "src/shader/shdr.mesh";
const meshOutputPath = "zig-out/shader/mesh.spv";
const meshFragInputPath = "src/shader/mesh.frag";
const meshFragOutputPath = "zig-out/shader/mesh_frag.spv";

pub const ComputePipeline = struct {
    handle: c.VkPipeline,
    layout: c.VkPipelineLayout,
    timeStamp: i128,
};

pub const GraphicsPipeline = struct {
    handle: c.VkPipeline,
    layout: c.VkPipelineLayout,
    format: c.VkFormat,
    timeStamp: i128,
};

pub const MeshPipeline = struct {
    handle: c.VkPipeline,
    layout: c.VkPipelineLayout,
    format: c.VkFormat,
    timeStamp: i128,
};

pub const PipelineEnum = enum { compute, graphics, mesh };

pub const PipelineManager = struct {
    alloc: Allocator,
    gpi: c.VkDevice,
    graphics: GraphicsPipeline,
    compute: ComputePipeline,
    mesh: MeshPipeline,
    cache: c.VkPipelineCache,

    pub fn init(alloc: Allocator, context: *const Context, descriptorManager: *const DescriptorManager, format: c.VkFormat) !PipelineManager {
        const gpi = context.gpi;

        const cache = try createPipelineCache(gpi);
        //Compute
        const computePipelineLayout = try createPipelineLayout(gpi, descriptorManager.computeLayout, 1);
        const computeShaderModule = try createShaderModule(alloc, computeInputPath, computeOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, computeShaderModule, null);
        const computeStage = [_]c.VkPipelineShaderStageCreateInfo{
            createShaderStage(c.VK_SHADER_STAGE_COMPUTE_BIT, computeShaderModule, "main"),
        };
        const computePipeline = try createPipeline(gpi, computePipelineLayout, &computeStage, cache, .compute, null);
        const computeTimeStamp = try getFileTimeStamp(alloc, computeInputPath);

        //Graphics
        const vertShdr = try createShaderModule(alloc, graphicsVertPath, graphicsVertOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, vertShdr, null);
        const fragShdr = try createShaderModule(alloc, graphicsFragPath, graphicsFragOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, fragShdr, null);
        const graphicsTimeStamp = try getFileTimeStamp(alloc, graphicsFragPath);

        const graphicsStages = [_]c.VkPipelineShaderStageCreateInfo{
            createShaderStage(c.VK_SHADER_STAGE_VERTEX_BIT, vertShdr, "main"),
            createShaderStage(c.VK_SHADER_STAGE_FRAGMENT_BIT, fragShdr, "main"),
        };

        const graphicsPipelineLayout = try createPipelineLayout(gpi, null, 0);
        const graphicsPipeline = try createPipeline(gpi, graphicsPipelineLayout, &graphicsStages, cache, .graphics, format);

        //Mesh
        const meshShdr = try createShaderModule(alloc, meshInputPath, meshOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, meshShdr, null);

        const meshFragShdr = try createShaderModule(alloc, meshFragInputPath, meshFragOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, meshFragShdr, null);
        const meshTimeStamp = try getFileTimeStamp(alloc, meshFragInputPath);

        const meshStages = [_]c.VkPipelineShaderStageCreateInfo{
            createShaderStage(c.VK_SHADER_STAGE_MESH_BIT_EXT, meshShdr, "main"),
            createShaderStage(c.VK_SHADER_STAGE_FRAGMENT_BIT, meshFragShdr, "main"),
        };

        const meshPipelineLayout = try createPipelineLayout(gpi, null, 0); // Simple layout with no descriptors
        const meshPipeline = try createPipeline(gpi, meshPipelineLayout, &meshStages, cache, .mesh, format);

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .compute = .{
                .handle = computePipeline,
                .layout = computePipelineLayout,
                .timeStamp = computeTimeStamp,
            },
            .graphics = .{
                .handle = graphicsPipeline,
                .layout = graphicsPipelineLayout,
                .format = format,
                .timeStamp = graphicsTimeStamp,
            },
            .mesh = .{
                .handle = meshPipeline,
                .layout = meshPipelineLayout,
                .format = format,
                .timeStamp = meshTimeStamp,
            },
            .cache = cache,
        };
    }

    pub fn deinit(self: *PipelineManager) void {
        const gpi = self.gpi;
        c.vkDestroyPipeline(gpi, self.compute.handle, null);
        c.vkDestroyPipelineLayout(gpi, self.compute.layout, null);

        c.vkDestroyPipeline(gpi, self.graphics.handle, null);
        c.vkDestroyPipelineLayout(gpi, self.graphics.layout, null);

        c.vkDestroyPipeline(gpi, self.mesh.handle, null);
        c.vkDestroyPipelineLayout(gpi, self.mesh.layout, null);

        c.vkDestroyPipelineCache(gpi, self.cache, null);
    }

    pub fn checkShaderUpdate(self: *PipelineManager, pipeline: PipelineEnum) !void {
        const tracyZ1 = ztracy.ZoneNC(@src(), "checkShaderUpdate", 0x0000FFFF);
        defer tracyZ1.End();

        var timeStamp: i128 = undefined;

        switch (pipeline) {
            .graphics => {
                timeStamp = try getFileTimeStamp(self.alloc, graphicsFragPath);
                if (timeStamp == self.graphics.timeStamp) return;
                self.graphics.timeStamp = timeStamp;
            },
            .compute => {
                timeStamp = try getFileTimeStamp(self.alloc, computeInputPath);
                if (timeStamp == self.compute.timeStamp) return;
                self.compute.timeStamp = timeStamp;
            },
            .mesh => {
                timeStamp = try getFileTimeStamp(self.alloc, meshFragInputPath);
                if (timeStamp == self.mesh.timeStamp) return;
                self.mesh.timeStamp = timeStamp;
            },
        }
        try self.updatePipeline(pipeline);
        std.debug.print("Shader Updated ^^\n", .{});
    }

    pub fn createShaderStage(stage: u32, module: c.VkShaderModule, name: [*]const u8) c.VkPipelineShaderStageCreateInfo {
        return c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = stage, //
            .module = module,
            .pName = name,
            .pSpecializationInfo = null, // for constants
        };
    }

    pub fn updatePipeline(self: *PipelineManager, pipeline: PipelineEnum) !void {
        _ = c.vkDeviceWaitIdle(self.gpi);
        const gpi = self.gpi;
        const alloc = self.alloc;

        switch (pipeline) {
            .compute => {
                c.vkDestroyPipeline(gpi, self.compute.handle, null);
                const computeShaderModule = try createShaderModule(alloc, computeInputPath, computeOutputPath, gpi);
                defer c.vkDestroyShaderModule(gpi, computeShaderModule, null);
                const computeStage = [_]c.VkPipelineShaderStageCreateInfo{
                    createShaderStage(c.VK_SHADER_STAGE_COMPUTE_BIT, computeShaderModule, "main"),
                };
                self.compute.handle = try createPipeline(gpi, self.compute.layout, &computeStage, self.cache, pipeline, null);
            },
            .graphics => {
                c.vkDestroyPipeline(gpi, self.graphics.handle, null);
                const vertShdr = try createShaderModule(alloc, graphicsVertPath, graphicsVertOutputPath, gpi);
                defer c.vkDestroyShaderModule(gpi, vertShdr, null);
                const fragShdr = try createShaderModule(alloc, graphicsFragPath, graphicsFragOutputPath, gpi);
                defer c.vkDestroyShaderModule(gpi, fragShdr, null);

                const shaderStages = [_]c.VkPipelineShaderStageCreateInfo{
                    createShaderStage(c.VK_SHADER_STAGE_VERTEX_BIT, vertShdr, "main"),
                    createShaderStage(c.VK_SHADER_STAGE_FRAGMENT_BIT, fragShdr, "main"),
                };
                self.graphics.handle = try createPipeline(gpi, self.graphics.layout, &shaderStages, self.cache, pipeline, self.graphics.format);
            },
            .mesh => {
                c.vkDestroyPipeline(gpi, self.mesh.handle, null);
                const meshShdr = try createShaderModule(alloc, meshInputPath, meshOutputPath, gpi);
                defer c.vkDestroyShaderModule(gpi, meshShdr, null);
                const meshFragShdr = try createShaderModule(alloc, meshFragInputPath, meshFragOutputPath, gpi);
                defer c.vkDestroyShaderModule(gpi, meshFragShdr, null);

                const meshShaderStages = [_]c.VkPipelineShaderStageCreateInfo{
                    createShaderStage(c.VK_SHADER_STAGE_MESH_BIT_EXT, meshShdr, "main"),
                    createShaderStage(c.VK_SHADER_STAGE_FRAGMENT_BIT, meshFragShdr, "main"),
                };
                self.mesh.handle = try createPipeline(gpi, self.mesh.layout, &meshShaderStages, self.cache, pipeline, self.mesh.format);
            },
        }
        std.debug.print("{s} Pipeline updated\n", .{@tagName(pipeline)});
    }
};

fn createPipelineCache(gpi: c.VkDevice) !c.VkPipelineCache {
    const cacheCreateInf = c.VkPipelineCacheCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
        .flags = 0,
        .initialDataSize = 0,
        .pInitialData = null,
    };
    var cache: c.VkPipelineCache = undefined;
    try check(c.vkCreatePipelineCache(gpi, &cacheCreateInf, null, &cache), "Failed to create Pipeline Cache");
    return cache;
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

fn createComputePipeline(gpi: c.VkDevice, layout: c.VkPipelineLayout, shaderModule: c.VkShaderModule, cache: c.VkPipelineCache) !c.VkPipeline {
    const pipeInf = c.VkComputePipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
            .module = shaderModule,
            .pName = "main",
        },
        .layout = layout,
    };

    var pipe: c.VkPipeline = undefined;
    try check(c.vkCreateComputePipelines(gpi, cache, 1, &pipeInf, null, &pipe), "Failed to create pipeline");
    return pipe;
}

fn createPipeline(
    gpi: c.VkDevice,
    layout: c.VkPipelineLayout,
    shaderStages: []const c.VkPipelineShaderStageCreateInfo,
    cache: c.VkPipelineCache,
    pipelineType: PipelineEnum,
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

pub fn getFileTimeStamp(alloc: Allocator, src: []const u8) !i128 {
    // Using helper to get the full path
    const abs_path = try resolveAssetPath(alloc, src);
    defer alloc.free(abs_path);

    const cwd = std.fs.cwd();
    const stat = try cwd.statFile(abs_path);
    const lastModified: i128 = stat.mtime;
    return lastModified;
}

pub fn resolveAssetPath(alloc: Allocator, asset_path: []const u8) ![]u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exe_dir);

    // Project root (up two levels from zig-out/bin)
    const project_root = try std.fs.path.resolve(alloc, &[_][]const u8{ exe_dir, "..", ".." });
    defer alloc.free(project_root);

    return std.fs.path.join(alloc, &[_][]const u8{ project_root, asset_path });
}
