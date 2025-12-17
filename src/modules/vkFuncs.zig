const vkT = @import("vkTypes.zig").c;

pub const VK_PIPELINE_LAYOUT_NULL_HANDLE: vkT.VkPipelineLayout = null;

pub var vkCmdDrawMeshTasksEXT: vkT.PFN_vkCmdDrawMeshTasksEXT = null;

pub var vkCreateShadersEXT: vkT.PFN_vkCreateShadersEXT = null;
pub var vkDestroyShaderEXT: vkT.PFN_vkDestroyShaderEXT = null;
pub var vkCmdBindShadersEXT: vkT.PFN_vkCmdBindShadersEXT = null;
pub var vkCmdSetVertexInputEXT: vkT.PFN_vkCmdSetVertexInputEXT = null;

pub var vkCmdSetRasterizerDiscardEnable: vkT.PFN_vkCmdSetRasterizerDiscardEnable = null;
pub var vkCmdSetCullMode: vkT.PFN_vkCmdSetCullMode = null;
pub var vkCmdSetFrontFace: vkT.PFN_vkCmdSetFrontFace = null;
pub var vkCmdSetDepthTestEnable: vkT.PFN_vkCmdSetDepthTestEnable = null;
pub var vkCmdSetDepthWriteEnable: vkT.PFN_vkCmdSetDepthWriteEnable = null;
pub var vkCmdSetDepthBoundsTestEnable: vkT.PFN_vkCmdSetDepthBoundsTestEnable = null;
pub var vkCmdSetStencilTestEnable: vkT.PFN_vkCmdSetStencilTestEnable = null;
pub var vkCmdSetColorBlendEnableEXT: vkT.PFN_vkCmdSetColorBlendEnableEXT = null;
pub var vkCmdSetColorBlendEquationEXT: vkT.PFN_vkCmdSetColorBlendEquationEXT = null;
pub var vkCmdSetColorWriteMaskEXT: vkT.PFN_vkCmdSetColorWriteMaskEXT = null;
pub var vkCmdSetPrimitiveTopology: vkT.PFN_vkCmdSetPrimitiveTopology = null;
pub var vkCmdSetPrimitiveRestartEnable: vkT.PFN_vkCmdSetPrimitiveRestartEnable = null;

pub var vkCmdSetDepthBiasEnable: vkT.PFN_vkCmdSetDepthBiasEnable = null;
pub var vkCmdSetPolygonModeEXT: vkT.PFN_vkCmdSetPolygonModeEXT = null;
pub var vkCmdSetRasterizationSamplesEXT: vkT.PFN_vkCmdSetRasterizationSamplesEXT = null;
pub var vkCmdSetSampleMaskEXT: vkT.PFN_vkCmdSetSampleMaskEXT = null;
pub var vkCmdSetDepthClampEnableEXT: vkT.PFN_vkCmdSetDepthClampEnableEXT = null;
pub var vkCmdSetAlphaToOneEnableEXT: vkT.PFN_vkCmdSetAlphaToOneEnableEXT = null;
pub var vkCmdSetAlphaToCoverageEnableEXT: vkT.PFN_vkCmdSetAlphaToCoverageEnableEXT = null;
pub var vkCmdSetLogicOpEnableEXT: vkT.PFN_vkCmdSetLogicOpEnableEXT = null;
pub var vkCmdSetViewportWithCount: vkT.PFN_vkCmdSetViewportWithCount = null;
pub var vkCmdSetScissorWithCount: vkT.PFN_vkCmdSetScissorWithCount = null;

pub var vkCmdBindDescriptorBuffersEXT: vkT.PFN_vkCmdBindDescriptorBuffersEXT = null;
pub var vkCmdSetDescriptorBufferOffsetsEXT: vkT.PFN_vkCmdSetDescriptorBufferOffsetsEXT = null;
pub var vkGetDescriptorEXT: vkT.PFN_vkGetDescriptorEXT = null;
pub var vkGetDescriptorSetLayoutSizeEXT: vkT.PFN_vkGetDescriptorSetLayoutSizeEXT = null;
pub var vkGetDescriptorSetLayoutBindingOffsetEXT: vkT.PFN_vkGetDescriptorSetLayoutBindingOffsetEXT = null;
