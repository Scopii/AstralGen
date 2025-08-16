const std = @import("std");

pub const c_api = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("vma/vk_mem_alloc.h");
});

extern fn SDL_ShowSimpleMessageBox(flags: u32, title: [*c]const u8, message: [*c]const u8, window: ?*anyopaque) c_int;

pub var pfn_vkCmdDrawMeshTasksEXT: c_api.PFN_vkCmdDrawMeshTasksEXT = null;

pub var pfn_vkCreateShadersEXT: c_api.PFN_vkCreateShadersEXT = null;
pub var pfn_vkDestroyShaderEXT: c_api.PFN_vkDestroyShaderEXT = null;
pub var pfn_vkCmdBindShadersEXT: c_api.PFN_vkCmdBindShadersEXT = null;
pub var pfn_vkCmdSetVertexInputEXT: c_api.PFN_vkCmdSetVertexInputEXT = null;

pub var pfn_vkCmdBindDescriptorBuffersEXT: c_api.PFN_vkCmdBindDescriptorBuffersEXT = null;
pub var pfn_vkCmdSetDescriptorBufferOffsetsEXT: c_api.PFN_vkCmdSetDescriptorBufferOffsetsEXT = null;
pub var pfn_vkGetDescriptorEXT: c_api.PFN_vkGetDescriptorEXT = null;
pub var pfn_vkGetDescriptorSetLayoutSizeEXT: c_api.PFN_vkGetDescriptorSetLayoutSizeEXT = null;

pub usingnamespace c_api;
