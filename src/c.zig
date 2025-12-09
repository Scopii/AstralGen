pub const c_api = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("vma/vk_mem_alloc.h");
});

pub const VK_PIPELINE_LAYOUT_NULL_HANDLE: c_api.VkPipelineLayout = null;

extern fn SDL_ShowSimpleMessageBox(flags: u32, title: [*c]const u8, message: [*c]const u8, window: ?*anyopaque) c_int;

pub var pfn_vkCmdDrawMeshTasksEXT: c_api.PFN_vkCmdDrawMeshTasksEXT = null;

pub var pfn_vkCreateShadersEXT: c_api.PFN_vkCreateShadersEXT = null;
pub var pfn_vkDestroyShaderEXT: c_api.PFN_vkDestroyShaderEXT = null;
pub var pfn_vkCmdBindShadersEXT: c_api.PFN_vkCmdBindShadersEXT = null;
pub var pfn_vkCmdSetVertexInputEXT: c_api.PFN_vkCmdSetVertexInputEXT = null;

pub var pfn_vkCmdSetRasterizerDiscardEnable: c_api.PFN_vkCmdSetRasterizerDiscardEnable = null;
pub var pfn_vkCmdSetCullMode: c_api.PFN_vkCmdSetCullMode = null;
pub var pfn_vkCmdSetFrontFace: c_api.PFN_vkCmdSetFrontFace = null;
pub var pfn_vkCmdSetDepthTestEnable: c_api.PFN_vkCmdSetDepthTestEnable = null;
pub var pfn_vkCmdSetDepthWriteEnable: c_api.PFN_vkCmdSetDepthWriteEnable = null;
pub var pfn_vkCmdSetDepthBoundsTestEnable: c_api.PFN_vkCmdSetDepthBoundsTestEnable = null;
pub var pfn_vkCmdSetStencilTestEnable: c_api.PFN_vkCmdSetStencilTestEnable = null;
pub var pfn_vkCmdSetColorBlendEnableEXT: c_api.PFN_vkCmdSetColorBlendEnableEXT = null;
pub var pfn_vkCmdSetColorWriteMaskEXT: c_api.PFN_vkCmdSetColorWriteMaskEXT = null;
pub var pfn_vkCmdSetPrimitiveTopology: c_api.PFN_vkCmdSetPrimitiveTopology = null;
pub var pfn_vkCmdSetPrimitiveRestartEnable: c_api.PFN_vkCmdSetPrimitiveRestartEnable = null;

pub var pfn_vkCmdSetDepthBiasEnable: c_api.PFN_vkCmdSetDepthBiasEnable = null;
pub var pfn_vkCmdSetPolygonModeEXT: c_api.PFN_vkCmdSetPolygonModeEXT = null;
pub var pfn_vkCmdSetRasterizationSamplesEXT: c_api.PFN_vkCmdSetRasterizationSamplesEXT = null;
pub var pfn_vkCmdSetSampleMaskEXT: c_api.PFN_vkCmdSetSampleMaskEXT = null;
pub var pfn_vkCmdSetDepthClampEnableEXT: c_api.PFN_vkCmdSetDepthClampEnableEXT = null;
pub var pfn_vkCmdSetAlphaToOneEnableEXT: c_api.PFN_vkCmdSetAlphaToOneEnableEXT = null;
pub var pfn_vkCmdSetAlphaToCoverageEnableEXT: c_api.PFN_vkCmdSetAlphaToCoverageEnableEXT = null;
pub var pfn_vkCmdSetLogicOpEnableEXT: c_api.PFN_vkCmdSetLogicOpEnableEXT = null;
pub var pfn_vkCmdSetViewportWithCount: c_api.PFN_vkCmdSetViewportWithCount = null;
pub var pfn_vkCmdSetScissorWithCount: c_api.PFN_vkCmdSetScissorWithCount = null;

pub var pfn_vkCmdBindDescriptorBuffersEXT: c_api.PFN_vkCmdBindDescriptorBuffersEXT = null;
pub var pfn_vkCmdSetDescriptorBufferOffsetsEXT: c_api.PFN_vkCmdSetDescriptorBufferOffsetsEXT = null;
pub var pfn_vkGetDescriptorEXT: c_api.PFN_vkGetDescriptorEXT = null;
pub var pfn_vkGetDescriptorSetLayoutSizeEXT: c_api.PFN_vkGetDescriptorSetLayoutSizeEXT = null;

pub usingnamespace c_api;
