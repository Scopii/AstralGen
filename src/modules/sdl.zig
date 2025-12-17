const headers = @import("c");
pub const c = headers.c;

extern fn SDL_ShowSimpleMessageBox(flags: u32, title: [*c]const u8, message: [*c]const u8, window: ?*anyopaque) c_int;
