pub const c = @import("c").c;
// Re-export C types

pub const VK_PIPELINE_LAYOUT_NULL_HANDLE: c.VkPipelineLayout = null;

// Draw Commands (Mesh & Indirect)
pub var vkCmdDrawMeshTasksEXT: c.PFN_vkCmdDrawMeshTasksEXT = null;
pub var vkCmdDrawMeshTasksIndirectEXT: c.PFN_vkCmdDrawMeshTasksIndirectEXT = null;

// Shader Object Management
pub var vkCreateShadersEXT: c.PFN_vkCreateShadersEXT = null;
pub var vkDestroyShaderEXT: c.PFN_vkDestroyShaderEXT = null;
pub var vkCmdBindShadersEXT: c.PFN_vkCmdBindShadersEXT = null;

// Descriptor Buffers
pub var vkCmdBindDescriptorBuffersEXT: c.PFN_vkCmdBindDescriptorBuffersEXT = null;
pub var vkCmdSetDescriptorBufferOffsetsEXT: c.PFN_vkCmdSetDescriptorBufferOffsetsEXT = null;
pub var vkGetDescriptorEXT: c.PFN_vkGetDescriptorEXT = null;
pub var vkGetDescriptorSetLayoutSizeEXT: c.PFN_vkGetDescriptorSetLayoutSizeEXT = null;
pub var vkGetDescriptorSetLayoutBindingOffsetEXT: c.PFN_vkGetDescriptorSetLayoutBindingOffsetEXT = null;

// Rasterization & Geometry State
pub var vkCmdSetPolygonModeEXT: c.PFN_vkCmdSetPolygonModeEXT = null;
pub var vkCmdSetCullMode: c.PFN_vkCmdSetCullMode = null;
pub var vkCmdSetFrontFace: c.PFN_vkCmdSetFrontFace = null;
pub var vkCmdSetPrimitiveTopology: c.PFN_vkCmdSetPrimitiveTopology = null;
pub var vkCmdSetPrimitiveRestartEnable: c.PFN_vkCmdSetPrimitiveRestartEnable = null;
pub var vkCmdSetRasterizerDiscardEnable: c.PFN_vkCmdSetRasterizerDiscardEnable = null;
pub var vkCmdSetRasterizationSamplesEXT: c.PFN_vkCmdSetRasterizationSamplesEXT = null;
pub var vkCmdSetSampleMaskEXT: c.PFN_vkCmdSetSampleMaskEXT = null;
pub var vkCmdSetVertexInputEXT: c.PFN_vkCmdSetVertexInputEXT = null;

// Depth & Stencil State
pub var vkCmdSetDepthTestEnable: c.PFN_vkCmdSetDepthTestEnable = null;
pub var vkCmdSetDepthWriteEnable: c.PFN_vkCmdSetDepthWriteEnable = null;
pub var vkCmdSetDepthBoundsTestEnable: c.PFN_vkCmdSetDepthBoundsTestEnable = null;
pub var vkCmdSetDepthBiasEnable: c.PFN_vkCmdSetDepthBiasEnable = null;
pub var vkCmdSetDepthBias: c.PFN_vkCmdSetDepthBias = null; // Value
pub var vkCmdSetDepthClampEnableEXT: c.PFN_vkCmdSetDepthClampEnableEXT = null;
pub var vkCmdSetStencilTestEnable: c.PFN_vkCmdSetStencilTestEnable = null;

// Color & Blending State
pub var vkCmdSetColorBlendEnableEXT: c.PFN_vkCmdSetColorBlendEnableEXT = null;
pub var vkCmdSetColorBlendEquationEXT: c.PFN_vkCmdSetColorBlendEquationEXT = null;
pub var vkCmdSetColorWriteMaskEXT: c.PFN_vkCmdSetColorWriteMaskEXT = null;
pub var vkCmdSetBlendConstants: c.PFN_vkCmdSetBlendConstants = null; // Value
pub var vkCmdSetLogicOpEnableEXT: c.PFN_vkCmdSetLogicOpEnableEXT = null;
pub var vkCmdSetAlphaToOneEnableEXT: c.PFN_vkCmdSetAlphaToOneEnableEXT = null;
pub var vkCmdSetAlphaToCoverageEnableEXT: c.PFN_vkCmdSetAlphaToCoverageEnableEXT = null;

// Viewport & Scissor
pub var vkCmdSetViewportWithCount: c.PFN_vkCmdSetViewportWithCount = null;
pub var vkCmdSetScissorWithCount: c.PFN_vkCmdSetScissorWithCount = null;

// Advanced / Debug / Voxel Optimization
pub var vkCmdSetLineWidth: c.PFN_vkCmdSetLineWidth = null;
pub var vkCmdSetConservativeRasterizationModeEXT: c.PFN_vkCmdSetConservativeRasterizationModeEXT = null;
pub var vkCmdSetFragmentShadingRateKHR: c.PFN_vkCmdSetFragmentShadingRateKHR = null;