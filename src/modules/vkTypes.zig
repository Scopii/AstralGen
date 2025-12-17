pub const c = @cImport({
    @cDefine("VMA_STATIC_VULKAN_FUNCTIONS", "0");
    @cDefine("VMA_DYNAMIC_VULKAN_FUNCTIONS", "1");
    @cInclude("vulkan/vulkan.h");
    @cInclude("vma/vk_mem_alloc.h");
});
