#include "imgui_bridge.h" // This includes vulkan.h and SDL.h first!

// Now include ImGui core (found in zgui pkg path)
#include "imgui.h"

// Now include backends (found in include/imgui/)
#include "imgui_impl_sdl3.h"
#include "imgui_impl_vulkan.h"

extern "C" bool bridge_ImGui_ImplSDL3_InitForVulkan(SDL_Window* window) {
    return ImGui_ImplSDL3_InitForVulkan(window);
}

extern "C" bool bridge_ImGui_ImplVulkan_Init(ZigImGuiInitInfo* info) {
    ImGui_ImplVulkan_InitInfo init_info = {};
    init_info.Instance = info->Instance;
    init_info.PhysicalDevice = info->PhysicalDevice;
    init_info.Device = info->Device;
    init_info.QueueFamily = info->QueueFamily;
    init_info.Queue = info->Queue;
    init_info.DescriptorPool = info->DescriptorPool;
    init_info.MinImageCount = info->MinImageCount;
    init_info.ImageCount = info->ImageCount;
    init_info.MSAASamples = VK_SAMPLE_COUNT_1_BIT;
    init_info.UseDynamicRendering = true;

    VkPipelineRenderingCreateInfo rendering_info = {};
    rendering_info.sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO;
    rendering_info.colorAttachmentCount = 1;
    rendering_info.pColorAttachmentFormats = &info->ColorAttachmentFormat;
    rendering_info.depthAttachmentFormat = info->DepthAttachmentFormat;
    
    init_info.PipelineRenderingCreateInfo = rendering_info;

    return ImGui_ImplVulkan_Init(&init_info);
}

extern "C" void bridge_ImGui_ImplVulkan_NewFrame() { 
    ImGui_ImplVulkan_NewFrame(); 
}

extern "C" void bridge_ImGui_ImplSDL3_NewFrame() { 
    ImGui_ImplSDL3_NewFrame(); 
}

extern "C" void bridge_ImGui_ImplVulkan_RenderDrawData(VkCommandBuffer cmd) {
    // Note: Use the C++ namespace for ImGui calls here
    ImGui_ImplVulkan_RenderDrawData(ImGui::GetDrawData(), cmd);
}

extern "C" void bridge_ImGui_ImplSDL3_ProcessEvent(SDL_Event* event) {
    ImGui_ImplSDL3_ProcessEvent(event);
}

extern "C" void bridge_ImGui_ImplVulkan_Shutdown() { 
    ImGui_ImplVulkan_Shutdown(); 
}

extern "C" void bridge_ImGui_ImplSDL3_Shutdown() { 
    ImGui_ImplSDL3_Shutdown(); 
}