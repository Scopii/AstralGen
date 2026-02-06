pub const c = @cImport({
    @cDefine("VMA_STATIC_VULKAN_FUNCTIONS", "0");
    @cDefine("VMA_DYNAMIC_VULKAN_FUNCTIONS", "1");
    
    @cDefine("IMGUI_HAS_DOCKING", "1");
    @cDefine("IMGUI_USE_WCHAR32", "1");
    @cDefine("IMGUI_DISABLE_OBSOLETE_FUNCTIONS", "1");

    @cInclude("vulkan/vulkan.h");
    @cInclude("vma/vk_mem_alloc.h");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    
    @cInclude("imgui_bridge.h");
});