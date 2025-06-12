// Add VMA configuration before including
pub const VMA_IMPLEMENTATION = 1;
pub const VMA_STATIC_VULKAN_FUNCTIONS = 0; // Use dynamic loading
pub const VMA_DYNAMIC_VULKAN_FUNCTIONS = 1;

pub usingnamespace @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("vma/vk_mem_alloc.h");
});
