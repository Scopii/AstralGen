
#ifndef IMGUI_BRIDGE_H
#define IMGUI_BRIDGE_H

#define IMGUI_HAS_DOCKING
#define IMGUI_USE_WCHAR32
#define IMGUI_DISABLE_OBSOLETE_FUNCTIONS

#include <vulkan/vulkan.h>
#include <SDL3/SDL.h>

// We define a simple C-compatible version of the InitInfo
typedef struct {
    VkInstance Instance;
    VkPhysicalDevice PhysicalDevice;
    VkDevice Device;
    uint32_t QueueFamily;
    VkQueue Queue;
    VkDescriptorPool DescriptorPool;
    uint32_t MinImageCount;
    uint32_t ImageCount;
    VkFormat ColorAttachmentFormat;
    VkFormat DepthAttachmentFormat;
} ZigImGuiInitInfo;

// C-style function declarations that Zig can call
#ifdef __cplusplus
extern "C" {
#endif

bool bridge_ImGui_ImplSDL3_InitForVulkan(SDL_Window* window);
bool bridge_ImGui_ImplVulkan_Init(ZigImGuiInitInfo* info);
void bridge_ImGui_ImplVulkan_NewFrame();
void bridge_ImGui_ImplSDL3_NewFrame();
void bridge_ImGui_ImplVulkan_RenderDrawData(VkCommandBuffer cmd);
void bridge_ImGui_ImplSDL3_ProcessEvent(SDL_Event* event);
void bridge_ImGui_ImplVulkan_Shutdown();
void bridge_ImGui_ImplSDL3_Shutdown();

#ifdef __cplusplus
}
#endif

#endif