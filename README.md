
***

# AstralGen

A Ray March based rendering Engine using Zig and Vulkan.

---

This project is mainly for educational purposes because I wanted to try something more modern after my previous OpenGL Projects and trying out Zig because of my frustration with the C++ (mostly the build System and header Files). I want to extend this into an Asset Editor for an actual proper Game Engine that I can use for myself.

## Libs Used

*   **Zig** `0.14.1`
*   **SDL 3** (c-imported)
*   **Vulkan** `1.3` (c-imported)
*   Many branches from the **zig-gamedev** repo

## Rendering

Rendering is done via `Synchronization2` so Renderpasses are left out. `Timeline-Semaphores` are used for general Synchronization while `Binary-Semaphores` are used for frame acquisition and Swapchain-Image signaling.

## Note

Because Im still realtively new to systems and engine programming ... I try to be productive first then clean code iteratively.
