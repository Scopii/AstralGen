// Vulkan Validation Layers
pub const DEBUG_MODE = false;
pub const EXTRA_VALIDATION = false;
pub const BEST_PRACTICES = false;

// Dev Mode
pub const CLOSE_WITH_CONSOLE = false;

// All Events of the Application
pub const AppEvent = enum {
    camForward,
    camBackward,
    camLeft,
    camRight,
    camUp,
    camDown,
    camFovIncrease,
    camFovDecrease,

    toggleFullscreen,
    closeApp,
    restartApp,
};
