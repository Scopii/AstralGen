// pub const PassEnum = enum {
//     QuantComp,
//     QuantGridMain,
//     QuantGridDebug,
//     QuantPlaneMain,
//     QuantPlaneDebug,

//     FrustumView,

//     DepthView,

//     CompRayMarch,

//     EditorGridGridDebug,
//     EditorGridPlaneDebug,

//     Imgui, // SPECIAL CASE
//     Composite, // SPECIAL CASE
// };

pub const BufferEnum = enum {
    QuantIndirectInputSB,
    QuantIndirectOutputSB,

    ReadbackSB, // 1

    EntitySB, // 2
    MainCamUB, // 3
    DebugCamUB, // 4

    ImguiVB, // 5
    ImguiIB, // 6
};

pub const TextureEnum = enum {
    RayMarchInputTex, // 0

    GridTex, // 1
    GridDepthTex, // 2

    DebugGridInputTex, // 3
    DebugGridOutputTex,
    DebugGridDepthTex, // 4
    DebugGridDepthOutputTex,

    PlaneTex, // 5
    PlaneDepthTex, // 6

    DebugPlaneInputTex, // 7
    DebugPlaneOutputTex,
    DebugPlaneOutputFrustumViewTex,
    DebugPlaneDepthTex, // 8

    DepthViewTex, // 9

    TestTileTex, // 10

    ImguiFontTex, // 11

    Swapchain, // SPECIAL CASE (Unsigned)
};

pub const UpdateRequestEnum = enum {
    EntityUpdate,
    CamMainUpdate,
    CanDebugUpdate,
    TestTileUpdate,
    GuiUpdate,
};
