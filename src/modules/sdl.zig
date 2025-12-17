pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

extern fn SDL_ShowSimpleMessageBox(flags: u32, title: [*c]const u8, message: [*c]const u8, window: ?*anyopaque) c_int;
