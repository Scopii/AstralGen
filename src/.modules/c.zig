pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vk_mem_alloc.h");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
});