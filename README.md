
# AstralGen

A Ray March based rendering Engine using Zig and Vulkan 1.3.

---

This project is mainly for educational purposes because I wanted to try something more modern after my previous OpenGL Projects and trying out Zig because I wanted to see how bad C++ really is compared to other Languages. 
This is also the next logical step for my personal growth towards becomming a proper graphics engineer. 
I want to extend this into an Asset Editor for an actual proper Game Engine that I can use for myself at some point.

## Libs Used

*   **Zig** `0.14.1`
*   **SDL 3** (c-imported)
*   **Vulkan** `1.3` (c-imported)
*   **VMA** integration
*   Many branches from the **zig-gamedev** repo

## Rendering

Rendering is done via Synchronization2 so Renderpasses are left out. Timeline-Semaphores are used for general Synchronization while Binary-Semaphores are used for frame acquisition and Swapchain-Image signaling.

## Finished Features:
*  Shader Hot Loading during runtime + Pipeline Caching for faster swaps
*  3 Different draw options using 3 different Pipelines (Classic, Mesh Shaders and Compute rendering to Image which is copied to the Swapchain)
*  State based command recording (only re-recording when needed)
*  Correct Swapchain recreation and window resizing
*  Automatic "Idle" state whenever the application is minimized (draws no CPU or GPU resources)
*  Resources management and GPU memory allocation (using the VMA)

## Note

Because Im still realtively new to systems and engine programming ... I try to be productive first and then clean and improve my code iteratively.
