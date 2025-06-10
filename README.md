You are right. My apologies. GitHub uses a specific flavor of Markdown that has its own conventions for a clean, readable `README.md` file.

Here is a formatted version using standard GitHub Markdown practices, such as using H2 (`##`) for sections, inline code blocks for technical terms, and a horizontal rule for separation, while preserving your original text.

***

# AstralGen

A Ray March based rendering Engine using Zig and Vulkan.

---

This project is mainly for educational purposes because I wanted to try something more modern after my previous OpenGL Projects and trying out Zig because of my frustration with the C++ (mostly the build System and header Files). I want to extend this into an Asset Editor for an actual proper Game Engine that I can use for myself.

## Technologies Used

*   **Zig** `0.14.1`
*   **SDL 3** (c-imported)
*   **Vulkan** `1.3` (c-imported)
*   Many branches from the **zig-gamedev** repo

## Rendering Details

Rendering is done via `Synchronization2` so Renderpasses are left out. `Timeline-Semaphores` are used for general Synchronization while `Binary-Semaphores` are used for frame acquisition and Swapchain-Image signaling.

## Development Note

Because Im still realtively new to systems and engine programming ... I try to be productive first then clean code iteratively.
