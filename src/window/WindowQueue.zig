
pub const WindowQueue = struct {

};

pub const WindowEvent = union(enum) {
    addWindow,
    removeWindow,
    hideAllWindows,
    showAllWindows,
    toggleMainFullscreen,
    pollEvents,
    toggleUi,
};
