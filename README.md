
# AstralGen

**A Ray March based rendering Engine using Zig and Vulkan 1.3.**
This project is mainly for educational purposes because I wanted to try Vulkan after my previous OpenGL Projects. I choose Zig because I wanted to try a more modern low level language after mostly doing Kotlin in Uni (great language btw) and C++ for my last project. 
This is also the next logical step for my personal growth towards becomming a proper graphics/rendering engineer and my dream of making a game with my own Game Engine.

## Techstack used

*   **Zig** `0.14.1`
*   **SDL 3** (c imported)
*   **Vulkan** `1.3` (c imported)
*   **VMA** integration (c++ imported)
*   and branches from the **zig-gamedev** repo

## Rendering with modern Vulkan

I am using Vulkan 1.3 with and a couple features that massively simplify Vulkan boilerplate, but also make the API just better and more pleasent to use overall:
*   **Synchronization2**: Core Feature since Vulkan 1.3, massively simplifying Memory Barriers/Synchronization and removing Vulkan Renderpasses and their Subsystems from the API
*   **Shader Objects**: These allow remove Pipeline Objects from the API replacing baked Pipelines with Shaders and overall Render States that can be set dynamically during the Command Recording
*   **Descriptor Buffers and Descriptor Indexing**: These effectively remove Descriptor Sets from the API and create giant Descriptor Buffers that can be used by index or by GPU pointers only needing very few of them
*   **Mesh Shaders**: These offer an alternative to the classic graphics pipeline on the GPU and adding specific shader stages that are more flexible and more compute like which can output Geometry
*   **Timeline Semaphores**: These Semaphores add an additional Integer as Semaphore Payload and so enable to Sync Host and Device but also Gpu Queues with just the one Semaphore (+ the ones needed for Frames in Flight and the Swapchains)
*   **Shader Storage non Uniform Indexing**: Allows non uniform sizes of each individual Descriptor Element

I have implemented 4 basic test passes that draw my SDF objects naively for all 4 "Pass Types" Compute, Vertex -> Fragment, Mesh -> Fragment, Task -> Mesh -> Fragment.
I have also implemented a basic Test-Grid using the Task -> Mesh -> Fragment Shader Stages.

## The Engine currently offers:

*  Shader compilation and hot loading during runtime supporting HLSL, GLSL and SLANG to spv
*  A full fledged Multi Window-System in wich every Window can "link" to any output Image 
*  Automatic "Idle" state whenever every window is minimized (draws no CPU or GPU resources)
*  Resources management and GPU memory allocation (using the VMA)
*  A working Camera that can be used via Push Constants and that is fully moveable through Event Mappings
*  A full fledged Event-System that can take in any Event and map them to output Events for the Application to know how to react to (Using a config)
*  Config settings for many allocations and system settings that can be changed on compile Time
*  A "simple" version of a Render Graph creating a "Pass" inside the Config freely by combining shaders, render Images and ordering them in a render sequence array
*  Simple Systems for random number generation, time and memory and entity management
*  "MapArrays": automatically typed and minimum sized sparse dense array for Entity / Instance / Object Management that has very fast accesstimes (warning, use validation functions actively if needed)

## What I plan for the future:

* A full fledged proper Render Graph with Resource Dependancys and Shader Stage Flags and usage Types for Resources (Next, but requires massive changes)
* Finishing my University Rendering Project using my alternative approach to massive SDF-based particle systems
* Implementing my own UI-System
* Asset Editor using SDFs
* Scene Editor and System using the SDF assets
* Animation Editor and System using the SDF assets
* Game Logic / Combat Systems

## Note

Im still realtively new to systems and engine and graphics programming ... so I try to be productive first and then clean and improve my code iteratively.
