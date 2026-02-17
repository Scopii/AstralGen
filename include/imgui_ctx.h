#pragma once
#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ImGuiContext ImGuiContext;
    typedef struct ImFontAtlas ImFontAtlas;

    ImGuiContext *igui_create_context(ImFontAtlas *shared_font_atlas);
    void igui_destroy_context(ImGuiContext *ctx);
    void igui_set_current_context(ImGuiContext *ctx);
    ImGuiContext *igui_get_current_context(void);

#ifdef __cplusplus
}
#endif