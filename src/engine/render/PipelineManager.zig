const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("../error.zig").check;
const createShaderModule = @import("../../shader/shader.zig").createShaderModule;
const ztracy = @import("ztracy");
const Context = @import("Context.zig").Context;

const computeInputPath = "src/shader/shdr.comp";
const computeOutputPath = "zig-out/shader/comp.spv";

const graphicsVertexInputPath = "src/shader/shdr.vert";
const graphicsVertexOutputPath = "zig-out/shader/vert.spv";
const graphicsFragInputPath = "src/shader/shdr.frag";
const graphicsFragOutputPath = "zig-out/shader/frag.spv";

const meshInputPath = "src/shader/shdr.mesh";
const meshOutputPath = "zig-out/shader/mesh.spv";
const meshFragInputPath = "src/shader/mesh.frag";
const meshFragOutputPath = "zig-out/shader/mesh_frag.spv";

pub const ComputePipeline = struct {
    handle: c.VkPipeline,
    layout: c.VkPipelineLayout,
    descriptorSetLayout: c.VkDescriptorSetLayout,
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

    pub fn init(alloc: Allocator, context: *const Context, format: c.VkFormat) !PipelineManager {
        const gpi = context.gpi;

        const cache = try createPipelineCache(gpi);
        //Compute
        const computeDescriptorSetLayout = try createComputeDescriptorSetLayout(gpi);
        const computePipelineLayout = try createPipelineLayout(gpi, computeDescriptorSetLayout, 1);
        const computeShaderModule = try createShaderModule(alloc, computeInputPath, computeOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, computeShaderModule, null);
        const computePipeline = try createComputePipeline(gpi, computePipelineLayout, computeShaderModule, cache);
        const computeTimeStamp = try getFileTimeStamp(alloc, computeInputPath);

        //Graphics
        const vertShdr = try createShaderModule(alloc, graphicsVertexInputPath, graphicsVertexOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, vertShdr, null);
        const fragShdr = try createShaderModule(alloc, graphicsFragInputPath, graphicsFragOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, fragShdr, null);
        const graphicsTimeStamp = try getFileTimeStamp(alloc, graphicsFragInputPath);

        const shaderStages = [_]c.VkPipelineShaderStageCreateInfo{
            createShaderStage(c.VK_SHADER_STAGE_VERTEX_BIT, vertShdr, "main"),
            createShaderStage(c.VK_SHADER_STAGE_FRAGMENT_BIT, fragShdr, "main"),
        };

        const graphicsPipelineLayout = try createPipelineLayout(gpi, null, 0);
        const graphicsPipeline = try createGraphicsPipeline(gpi, graphicsPipelineLayout, &shaderStages, format, cache);

        //Mesh
        const meshShdr = try createShaderModule(alloc, meshInputPath, meshOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, meshShdr, null);

        const meshFragShdr = try createShaderModule(alloc, meshFragInputPath, meshFragOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, meshFragShdr, null);
        const meshTimeStamp = try getFileTimeStamp(alloc, meshFragInputPath);

        const meshShaderStages = [_]c.VkPipelineShaderStageCreateInfo{ createShaderStage(c.VK_SHADER_STAGE_MESH_BIT_EXT, meshShdr, "main"), createShaderStage(c.VK_SHADER_STAGE_FRAGMENT_BIT, meshFragShdr, "main") };

        const meshPipelineLayout = try createPipelineLayout(gpi, null, 0); // Simple layout with no descriptors
        const meshPipeline = try createMeshPipeline(gpi, meshPipelineLayout, &meshShaderStages, format, cache);

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .compute = .{
                .handle = computePipeline,
                .layout = computePipelineLayout,
                .descriptorSetLayout = computeDescriptorSetLayout,
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
        c.vkDestroyDescriptorSetLayout(gpi, self.compute.descriptorSetLayout, null);

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
                timeStamp = try getFileTimeStamp(self.alloc, graphicsFragInputPath);
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
        switch (pipeline) {
            .graphics => try self.updateGraphicsPipeline(),
            .compute => try self.updateComputePipeline(),
            .mesh => try self.updateMeshPipeline(),
        }
    }

    pub fn updateComputePipeline(self: *PipelineManager) !void {
        const gpi = self.gpi;
        const alloc = self.alloc;
        c.vkDestroyPipeline(gpi, self.compute.handle, null);
        const computeShaderModule = try createShaderModule(alloc, computeInputPath, computeOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, computeShaderModule, null);
        self.compute.handle = try createComputePipeline(gpi, self.compute.layout, computeShaderModule, self.cache);
        std.debug.print("Compute Pipeline updated\n", .{});
    }

    pub fn updateGraphicsPipeline(self: *PipelineManager) !void {
        const gpi = self.gpi;
        const alloc = self.alloc;
        c.vkDestroyPipeline(gpi, self.graphics.handle, null);
        const vertShdr = try createShaderModule(alloc, graphicsVertexInputPath, graphicsVertexOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, vertShdr, null);
        const fragShdr = try createShaderModule(alloc, graphicsFragInputPath, graphicsFragOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, fragShdr, null);

        const shaderStages = [_]c.VkPipelineShaderStageCreateInfo{
            createShaderStage(c.VK_SHADER_STAGE_VERTEX_BIT, vertShdr, "main"),
            createShaderStage(c.VK_SHADER_STAGE_FRAGMENT_BIT, fragShdr, "main"),
        };
        self.graphics.handle = try createGraphicsPipeline(gpi, self.graphics.layout, &shaderStages, self.graphics.format, self.cache);
        std.debug.print("Graphics Pipeline updated\n", .{});
    }

    pub fn updateMeshPipeline(self: *PipelineManager) !void {
        const gpi = self.gpi;
        const alloc = self.alloc;
        c.vkDestroyPipeline(gpi, self.mesh.handle, null);
        const meshShdr = try createShaderModule(alloc, meshInputPath, meshOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, meshShdr, null);
        const meshFragShdr = try createShaderModule(alloc, meshFragInputPath, meshFragOutputPath, gpi);
        defer c.vkDestroyShaderModule(gpi, meshFragShdr, null);

        const meshShaderStages = [_]c.VkPipelineShaderStageCreateInfo{
            createShaderStage(c.VK_SHADER_STAGE_MESH_BIT_EXT, meshShdr, "main"),
            createShaderStage(c.VK_SHADER_STAGE_FRAGMENT_BIT, meshFragShdr, "main"),
        };
        self.mesh.handle = try createMeshPipeline(gpi, self.mesh.layout, &meshShaderStages, self.mesh.format, self.cache);
        std.debug.print("Mesh Pipeline updated\n", .{});
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

fn createComputeDescriptorSetLayout(gpi: c.VkDevice) !c.VkDescriptorSetLayout {
    const binding = c.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
        .pImmutableSamplers = null,
    };

    const layoutInf = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &binding,
    };

    var descriptorSetLayout: c.VkDescriptorSetLayout = undefined;
    try check(c.vkCreateDescriptorSetLayout(gpi, &layoutInf, null, &descriptorSetLayout), "Failed to create descriptor set layout");
    return descriptorSetLayout;
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

fn createMeshPipeline(
    gpi: c.VkDevice,
    layout: c.VkPipelineLayout,
    shaderStages: []const c.VkPipelineShaderStageCreateInfo,
    format: c.VkFormat,
    cache: c.VkPipelineCache,
) !c.VkPipeline {
    // Viewport and Scissor will be dynamic
    const viewInf = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };

    // Standard rasterization state
    const rasterInf = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .cullMode = c.VK_CULL_MODE_NONE,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        .lineWidth = 1.0,
    };

    // Standard multisampling state
    const msaaInf = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = c.VK_FALSE,
    };

    // Standard color blend state
    const colBlendAttach = c.VkPipelineColorBlendAttachmentState{
        .blendEnable = c.VK_FALSE,
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT |
            c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
    };

    const colBlendInf = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &colBlendAttach,
    };

    // Dynamic states
    const dynStates = [_]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };

    const dynStateInf = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynStates.len,
        .pDynamicStates = &dynStates,
    };

    // Rendering format info
    const colFormats = [_]c.VkFormat{format};
    var pipeline_rendering_info = c.VkPipelineRenderingCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = &colFormats,
    };

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
}

fn createGraphicsPipeline(gpi: c.VkDevice, layout: c.VkPipelineLayout, shaderStages: []const c.VkPipelineShaderStageCreateInfo, format: c.VkFormat, cache: c.VkPipelineCache) !c.VkPipeline {
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

    const colFormats = [_]c.VkFormat{format};
    var pipeline_rendering_info = c.VkPipelineRenderingCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .viewMask = 0,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = &colFormats,
        .depthAttachmentFormat = c.VK_FORMAT_UNDEFINED,
        .stencilAttachmentFormat = c.VK_FORMAT_UNDEFINED,
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
