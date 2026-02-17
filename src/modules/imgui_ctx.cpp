#include "imgui_ctx.h"
#include "imgui.h"

extern "C"
{

    ImGuiContext *igui_create_context(ImFontAtlas *shared_font_atlas)
    {
        return ImGui::CreateContext(shared_font_atlas);
    }

    void igui_destroy_context(ImGuiContext *ctx)
    {
        ImGui::DestroyContext(ctx);
    }

    void igui_set_current_context(ImGuiContext *ctx)
    {
        ImGui::SetCurrentContext(ctx);
    }

    ImGuiContext *igui_get_current_context(void)
    {
        return ImGui::GetCurrentContext();
    }

    ImFontAtlas *igui_get_font_atlas(void)
    {
        return ImGui::GetIO().Fonts;
    }

    void igui_copy_backend_to_context(ImGuiContext *dst)
    {
        ImGuiContext *src = ImGui::GetCurrentContext();
        ImGuiIO &srcIO = ImGui::GetIO();
        ImGui::SetCurrentContext(dst);
        ImGuiIO &dstIO = ImGui::GetIO();
        dstIO.BackendPlatformUserData = srcIO.BackendPlatformUserData; // SDL backend
        dstIO.BackendRendererUserData = srcIO.BackendRendererUserData; // Vulkan backend
        dstIO.BackendPlatformName = srcIO.BackendPlatformName;
        dstIO.BackendRendererName = srcIO.BackendRendererName;
        ImGui::SetCurrentContext(src); // restore
    }
}