const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const check = @import("../error.zig").check;
const createShaderModule = @import("../../shader/shader.zig").createShaderModule;

pub const ComputePipeline = struct {
    handle: c.VkPipeline,
    layout: c.VkPipelineLayout,
    descriptorSetLayout: c.VkDescriptorSetLayout,
};

pub const GraphicsPipeline = struct {
    handle: c.VkPipeline,
    layout: c.VkPipelineLayout,
};

pub const PipelineManager = struct {
    graphics: GraphicsPipeline,
    compute: ComputePipeline,

    pub fn init(alloc: Allocator, context: *const Context, format: c.VkFormat) !PipelineManager {
        const gpi = context.gpi;
        //Compute
        const computeDescriptorSetLayout = try createComputeDescriptorSetLayout(gpi);
        const computePipelineLayout = try createPipelineLayout(gpi, computeDescriptorSetLayout, 1);
        const computeShaderModule = try createShaderModule(alloc, "src/shader/shdr.comp", "zig-out/shader/comp.spv", gpi);
        defer c.vkDestroyShaderModule(gpi, computeShaderModule, null);
        const computePipeline = try createComputePipeline(gpi, computePipelineLayout, computeShaderModule);

        //Graphics
        const vertShdr = try createShaderModule(alloc, "src/shader/shdr.vert", "zig-out/shader/vert.spv", gpi);
        defer c.vkDestroyShaderModule(gpi, vertShdr, null);
        const fragShdr = try createShaderModule(alloc, "src/shader/shdr.frag", "zig-out/shader/frag.spv", gpi);
        defer c.vkDestroyShaderModule(gpi, fragShdr, null);

        const shaderStages = [_]c.VkPipelineShaderStageCreateInfo{
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                .module = vertShdr,
                .pName = "main",
                .pSpecializationInfo = null, // for constants
            },
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .module = fragShdr,
                .pName = "main",
                .pSpecializationInfo = null, // for constants
            },
        };

        const graphicsPipelineLayout = try createPipelineLayout(gpi, null, 0);
        const graphicsPipeline = try createGraphicsPipeline(gpi, graphicsPipelineLayout, &shaderStages, format);

        return .{
            .compute = .{
                .handle = computePipeline,
                .layout = computePipelineLayout,
                .descriptorSetLayout = computeDescriptorSetLayout,
            },
            .graphics = .{
                .handle = graphicsPipeline,
                .layout = graphicsPipelineLayout,
            },
        };
    }

    pub fn deinit(self: *PipelineManager, gpi: c.VkDevice) void {
        c.vkDestroyPipeline(gpi, self.compute.handle, null);
        c.vkDestroyPipelineLayout(gpi, self.compute.layout, null);
        c.vkDestroyDescriptorSetLayout(gpi, self.compute.descriptorSetLayout, null);

        c.vkDestroyPipeline(gpi, self.graphics.handle, null);
        c.vkDestroyPipelineLayout(gpi, self.graphics.layout, null);
    }
};

fn createComputeDescriptorSetLayout(gpi: c.VkDevice) !c.VkDescriptorSetLayout {
    const binding = c.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
        .pImmutableSamplers = null,
    };

    const layoutInfo = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &binding,
    };

    var descriptorSetLayout: c.VkDescriptorSetLayout = undefined;
    try check(c.vkCreateDescriptorSetLayout(gpi, &layoutInfo, null, &descriptorSetLayout), "Failed to create descriptor set layout");
    return descriptorSetLayout;
}

fn createPipelineLayout(gpi: c.VkDevice, descriptorSetLayout: c.VkDescriptorSetLayout, layoutCount: u32) !c.VkPipelineLayout {
    // Create pipeline layout
    const pipelineLayoutInfo = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = layoutCount,
        .pSetLayouts = &descriptorSetLayout,
        .pushConstantRangeCount = 0,
    };

    var layout: c.VkPipelineLayout = undefined;
    try check(c.vkCreatePipelineLayout(gpi, &pipelineLayoutInfo, null, &layout), "Failed to create pipeline layout");
    return layout;
}

fn createComputePipeline(gpi: c.VkDevice, layout: c.VkPipelineLayout, shaderModule: c.VkShaderModule) !c.VkPipeline {
    // Create compute pipeline
    const pipelineInfo = c.VkComputePipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
            .module = shaderModule,
            .pName = "main",
        },
        .layout = layout,
    };

    var pipeline: c.VkPipeline = undefined;
    try check(c.vkCreateComputePipelines(gpi, null, 1, &pipelineInfo, null, &pipeline), "Failed to create pipeline");
    return pipeline;
}

fn createGraphicsPipeline(gpi: c.VkDevice, layout: c.VkPipelineLayout, shaderStages: []const c.VkPipelineShaderStageCreateInfo, format: c.VkFormat) !c.VkPipeline {
    // VK_PRIMITIVE_TOPOLOGY_POINT_LIST         points from vertices
    // VK_PRIMITIVE_TOPOLOGY_LINE_LIST          line from every 2 vertices without reuse
    // VK_PRIMITIVE_TOPOLOGY_LINE_STRIP         the end vertex of every line is used as start vertex for the next line
    // VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST      triangle from every 3 vertices without reuse
    // VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP     second and third vertex of every triangle are used as first two vertices of the next triangle
    const vertInputInf = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 0,
        .vertexAttributeDescriptionCount = 0,
    };

    const assemblyInf = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
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
    var pipeline: c.VkPipeline = undefined;
    try check(c.vkCreateGraphicsPipelines(gpi, null, 1, &pipelineInf, null, &pipeline), "Failed to create Graphics Pipeline");
    return pipeline;
}
