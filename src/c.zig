const std = @import("std");

// Step 1: Put the C imports into a named constant.
// I've named it `c_api` for clarity.
pub const c_api = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("vma/vk_mem_alloc.h");
});

extern fn SDL_ShowSimpleMessageBox(flags: u32, title: [*c]const u8, message: [*c]const u8, window: ?*anyopaque) c_int;

// Step 2: Declare the function pointer variable as a separate public member of this file.
// It uses the PFN type from the c_api struct we just defined.
pub var pfn_vkCmdDrawMeshTasksEXT: c_api.PFN_vkCmdDrawMeshTasksEXT = null;

// Step 3 (Optional but recommended): For convenience, you can still use `usingnamespace`
// so you don't have to type `c_api.` everywhere in your project.
pub usingnamespace c_api;
