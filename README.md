
# AstralGen

**A Ray March based rendering Engine using Zig and Vulkan 1.3**
This project is mainly for educational purposes because I wanted to try Vulkan after my previous OpenGL Projects. I also choose Zig to try a more modern low level language after mostly doing Kotlin in Uni (great language IMO) and C++ for my last project. 
This is also the next logical step for my personal growth towards becomming a proper graphics/rendering engineer and my dream of making a game with my own Game Engine.

## Build & Run Steps (Tested on Windows and Linux)
1. Installing the **absolute NEWEST GPU Drivers**!
1. Installing **Vulkan SDK Version 1.4.341.0+**
2. Having specifically **Zig Version 15.2!**
3. In Console: zig build run
Thats it!

**Keyboard Controls, App Events:** src/configs/appConfig.zig
**Shader Definitions:** src/configs/shaderConfig.zig
**Graphics Settings, Passes/Resources:** src/configs/renderConfig.zig

## Techstack used

*   **Zig** `0.15.2`
*   **SDL 3** (c imported)
*   **Vulkan** `1.3` (c imported)
*   **VMA** integration (c++ imported)
*   and branches from the **zig-gamedev** repo

## Rendering with modern Vulkan

I am using Vulkan 1.3 with additional features that massively simplify Vulkan boilerplate, but also make the API just better and more pleasent to use overall:
*   **Synchronization2**: Core Feature since Vulkan 1.3, massively simplifying Memory Barriers/Synchronization and removing Vulkan Renderpasses and their Subsystems from the API
*   **Shader Objects**: These remove Pipeline Objects from the API replacing baked Pipelines with Shaders and allow setting graphics States that dynamically during Command Recording
*   **Descriptor Heaps**: Khronos version of DX12 Heaps (very new Extension), massively simplified logic that remove many objects like Pipeline Layouts and fully lean into Bindless
*   **Task/Mesh Shaders**: These offer an alternative to the classic graphics pipeline on the GPU and adding specific shader stages that are more flexible and more compute like which can generate Geometry
*   **Timeline Semaphores**: These Semaphores add an additional Integer and so enable to Sync Host and Device but also Gpu Queues with just the one Semaphore (+ the ones needed for Frames in Flight and the Swapchains)
*   **Shader Storage non Uniform Indexing**: Allows non uniform sizes of each individual Descriptor Element

I have implemented basic test passes:
Compute
Vertex -> Fragment
Mesh -> Fragment
Task -> Mesh -> Fragment
Indirect Compute Pass -> Indirect Task -> Mesh -> Fragment Pass
I have also implemented a basic Test-Grid using the Task -> Mesh -> Fragment Shader Stages.

## The Engine currently offers:

*  Shader compilation and hot loading during runtime supporting HLSL, GLSL and SLANG to spv
*  A full fledged multi Window-system in which every Window can "link" to any output Texture to blit from it 
*  Automatic "Idle" state whenever every Window is minimized (no CPU or GPU usage)
*  A working Camera that can be used and is fully moveable through Event Mappings
*  A full fledged Event-System that can take in any Event including Keybinds and map them to output Events for the Application to know how to react to (Using a config)
*  Config settings for many allocations and system settings that can be changed at compile time
*  Resource Management (Textures, Buffers) via configs which can be linked to Shader Slots inside the Pass Struct
*  Pass configs that contain shaders, buffer and texture usages, attachments and draw call / dispatch parameters.
*  Sequence Graph (Simple Render Graph) Which automatically generates correct barriers based on the Pass config (currently not optimizing them)
*  Named Profiling with Cmd Query Timestamps which can be freely set inside frames recording.
*  Simple Systems for random number generation, time, memory and entity management
*  "MapArrays": automatically typed and minimum sized sparse dense array for Entity / Instance / Object Management that has very fast access times (warning, use validation functions actively if needed)

## What I plan for the future:

* A proper Render Graph with Resource Dependancys
* Finishing my University Rendering Project using my alternative approach to massive SDF-based particle systems
* Implementing my own UI-System
* Asset Editor using SDFs
* Scene Editor and System using the SDF assets
* Animation Editor and System using the SDF assets
* Game Logic / Combat Systems

## Note

Im still realtively new to systems and engine and graphics programming ... so I try to be productive first and then clean and improve my code iteratively.
