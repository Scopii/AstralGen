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
}