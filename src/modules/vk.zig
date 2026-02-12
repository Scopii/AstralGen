pub const c = @import("c").c;
// Re-export C types

pub const VK_PIPELINE_LAYOUT_NULL_HANDLE: c.VkPipelineLayout = null;

// Draw Commands (Mesh & Indirect)
pub var vkCmdDrawMeshTasksEXT: c.PFN_vkCmdDrawMeshTasksEXT = null;
pub var vkCmdDrawMeshTasksIndirectEXT: c.PFN_vkCmdDrawMeshTasksIndirectEXT = null;

// Shader Objects
pub var vkCreateShadersEXT: c.PFN_vkCreateShadersEXT = null;
pub var vkDestroyShaderEXT: c.PFN_vkDestroyShaderEXT = null;
pub var vkCmdBindShadersEXT: c.PFN_vkCmdBindShadersEXT = null;

// Descriptor Heaps
pub var vkWriteResourceDescriptorsEXT: c.PFN_vkWriteResourceDescriptorsEXT = null;
pub var vkWriteSamplerDescriptorsEXT: c.PFN_vkWriteSamplerDescriptorsEXT = null;
pub var vkCmdBindResourceHeapEXT: c.PFN_vkCmdBindResourceHeapEXT = null;
pub var vkCmdBindSamplerHeapEXT: c.PFN_vkCmdBindSamplerHeapEXT = null;
pub var vkCmdPushDataEXT: c.PFN_vkCmdPushDataEXT = null;

// Extended Dynamic State 3
pub var vkCmdSetPolygonModeEXT: c.PFN_vkCmdSetPolygonModeEXT = null;
pub var vkCmdSetRasterizationSamplesEXT: c.PFN_vkCmdSetRasterizationSamplesEXT = null;
pub var vkCmdSetSampleMaskEXT: c.PFN_vkCmdSetSampleMaskEXT = null;
pub var vkCmdSetDepthClampEnableEXT: c.PFN_vkCmdSetDepthClampEnableEXT = null;
pub var vkCmdSetColorBlendEnableEXT: c.PFN_vkCmdSetColorBlendEnableEXT = null;
pub var vkCmdSetColorBlendEquationEXT: c.PFN_vkCmdSetColorBlendEquationEXT = null;
pub var vkCmdSetColorWriteMaskEXT: c.PFN_vkCmdSetColorWriteMaskEXT = null;
pub var vkCmdSetAlphaToOneEnableEXT: c.PFN_vkCmdSetAlphaToOneEnableEXT = null;
pub var vkCmdSetAlphaToCoverageEnableEXT: c.PFN_vkCmdSetAlphaToCoverageEnableEXT = null;

// Extended Dynamic State 2
pub var vkCmdSetVertexInputEXT: c.PFN_vkCmdSetVertexInputEXT = null;
pub var vkCmdSetLogicOpEnableEXT: c.PFN_vkCmdSetLogicOpEnableEXT = null;
pub var vkCmdSetLogicOpEXT: c.PFN_vkCmdSetLogicOpEXT = null;

// Conservative Rasterization
pub var vkCmdSetConservativeRasterizationModeEXT: c.PFN_vkCmdSetConservativeRasterizationModeEXT = null;

// Fragment Shading Rate
pub var vkCmdSetFragmentShadingRateKHR: c.PFN_vkCmdSetFragmentShadingRateKHR = null;

// Debug
pub var vkSetDebugUtilsObjectNameEXT: c.PFN_vkSetDebugUtilsObjectNameEXT = null;
