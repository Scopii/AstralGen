pub const c = @cImport({
    // Vulkan/VMA Config
    @cDefine("VMA_STATIC_VULKAN_FUNCTIONS", "0");
    @cDefine("VMA_DYNAMIC_VULKAN_FUNCTIONS", "1");
    @cInclude("vulkan/vulkan.h");
    @cInclude("vma/vk_mem_alloc.h");

    // SDL (Includes Vulkan logic too)
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
});
