const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;

// Embed compiled shaders as binary data aligned for GPU usage
const verSpv align(@alignOf(u32)) = @embedFile("vert_shdr").*;
const fragSpv align(@alignOf(u32)) = @embedFile("frag_shdr").*;

pub fn createShaderModule(codeSize: usize, pCode: [*]const u32, gpi: c.VkDevice) !c.VkShaderModule {
    const createInfo = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = codeSize,
        .pCode = pCode,
    };
    var shdrMod: c.VkShaderModule = undefined;
    try check(c.vkCreateShaderModule(gpi, &createInfo, null, &shdrMod), "Failed to create shader module");

    return shdrMod;
}

pub const Pipeline = struct {
    handle: c.VkPipeline,
    layout: c.VkPipelineLayout,

    pub fn init(gpi: c.VkDevice, format: c.VkFormat) !Pipeline {
        const vertShdr = try createShaderModule(verSpv.len, @ptrCast(@alignCast(&verSpv)), gpi);
        defer c.vkDestroyShaderModule(gpi, vertShdr, null);

        const fragShdr = try createShaderModule(fragSpv.len, @ptrCast(@alignCast(&fragSpv)), gpi);
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

        const layoutInfo = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 0,
            .pushConstantRangeCount = 0,
        };
        var layout: c.VkPipelineLayout = undefined;
        try check(c.vkCreatePipelineLayout(gpi, &layoutInfo, null, &layout), "Failed to create Pipeline Layout");

        // VK_PRIMITIVE_TOPOLOGY_POINT_LIST         points from vertices
        // VK_PRIMITIVE_TOPOLOGY_LINE_LIST          line from every 2 vertices without reuse
        // VK_PRIMITIVE_TOPOLOGY_LINE_STRIP         the end vertex of every line is used as start vertex for the next line
        // VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST      triangle from every 3 vertices without reuse
        // VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP     second and third vertex of every triangle are used as first two vertices of the next triangle
        const vertexInputInfo = c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = 0,
            .vertexAttributeDescriptionCount = 0,
        };

        const inputAssemblyInfo = c.VkPipelineInputAssemblyStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        };

        const viewportInfo = c.VkPipelineViewportStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount = 1,
        };

        const rasterInfo = c.VkPipelineRasterizationStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable = c.VK_FALSE,
            .rasterizerDiscardEnable = c.VK_FALSE,
            .polygonMode = c.VK_POLYGON_MODE_FILL,
            .cullMode = c.VK_CULL_MODE_BACK_BIT, // VK_CULL_MODE_NONE
            .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
            .depthBiasEnable = c.VK_FALSE,
            .depthBiasConstantFactor = 0.0,
            .depthBiasClamp = 0.0,
            .depthBiasSlopeFactor = 0.0,
            .lineWidth = 1.0,
        };

        const msaaInfo = c.VkPipelineMultisampleStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .flags = 0,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
            .sampleShadingEnable = c.VK_FALSE,
            .minSampleShading = 1.0,
            .pSampleMask = null,
            .alphaToCoverageEnable = c.VK_FALSE,
            .alphaToOneEnable = c.VK_FALSE,
        };

        const colorBlendAttachment = c.VkPipelineColorBlendAttachmentState{
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

        const colorBlendInfo = c.VkPipelineColorBlendStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = c.VK_FALSE,
            .logicOp = c.VK_LOGIC_OP_COPY,
            .attachmentCount = 1,
            .pAttachments = &colorBlendAttachment,
            .blendConstants = [4]f32{ 0.0, 0.0, 0.0, 0.0 },
        };

        const dynStates = [_]c.VkDynamicState{
            c.VK_DYNAMIC_STATE_VIEWPORT,
            c.VK_DYNAMIC_STATE_SCISSOR,
        };

        const dynStateInfo = c.VkPipelineDynamicStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynStates.len,
            .pDynamicStates = &dynStates,
        };

        const colorFormats = [_]c.VkFormat{format};
        var pipeline_rendering_info = c.VkPipelineRenderingCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
            .viewMask = 0,
            .colorAttachmentCount = 1,
            .pColorAttachmentFormats = &colorFormats,
            .depthAttachmentFormat = c.VK_FORMAT_UNDEFINED,
            .stencilAttachmentFormat = c.VK_FORMAT_UNDEFINED,
        };

        const pipelineInfo = c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = &pipeline_rendering_info,
            .stageCount = 2,
            .pStages = &shaderStages,
            .pVertexInputState = &vertexInputInfo,
            .pInputAssemblyState = &inputAssemblyInfo,
            .pViewportState = &viewportInfo,
            .pRasterizationState = &rasterInfo,
            .pMultisampleState = &msaaInfo,
            .pDepthStencilState = null,
            .pColorBlendState = &colorBlendInfo,
            .pDynamicState = &dynStateInfo,
            .layout = layout,
            .subpass = 0,
            .basePipelineIndex = -1,
        };

        var pipeline: c.VkPipeline = undefined;
        try check(c.vkCreateGraphicsPipelines(gpi, null, 1, &pipelineInfo, null, &pipeline), "Failed to create Graphics Pipeline");

        return .{
            .handle = pipeline,
            .layout = layout,
        };
    }
};
