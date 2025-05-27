// Imports
const std = @import("std");
const vk = @import("vulkan");
const c = @import("c.zig");
const Context = @import("engine/context.zig").Context;
const Swapchain = @import("engine/swapchain.zig").Swapchain;
const createPipeline = @import("engine/pipeline.zig").createPipeline;
const createRenderCmdBuffers = @import("engine/command.zig").createRenderCmdBuffers;
const destroyCmdBuffers = @import("engine/command.zig").destroyCmdBuffers;
const uploadVertexData = @import("engine/buffer.zig").uploadVertexData;
const copyBuffer = @import("engine/buffer.zig").copyBuffer;
const App = @import("core/app.zig").App;

// Mesh Data
const triangle_vertices = @import("engine/mesh/triangle.zig").triangle_vertices;

// Re-Formats
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var app = try App.init();
    defer app.deinit();

    // Set up memory allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Vulkan(Graphics) context (instance, device, queues, etc.)
    const gc = try Context.init(allocator, "AstralGen", app.window);
    defer gc.deinit();

    std.log.debug("Using GPU: {s}", .{gc.deviceName()});

    // Create swapchain for presenting images to the window
    var swapchain = try Swapchain.init(&gc, allocator, app.extend);
    defer swapchain.deinit();

    // Create pipeline layout (describes shader resources - none in this simple example)
    const pipeline_layout = try gc.dev.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    defer gc.dev.destroyPipelineLayout(pipeline_layout, null);

    // Create graphics pipeline using dynamic rendering (no render pass needed!)
    const graphics_pipeline = try createPipeline(&gc, pipeline_layout, swapchain.surface_format.format);
    defer gc.dev.destroyPipeline(graphics_pipeline, null);

    // Create command pool for allocating command buffers
    const cmd_pool = try gc.dev.createCmdPool(&.{
        .queue_family_index = gc.graphics_queue.family,
    }, null);
    defer gc.dev.destroyCmdPool(cmd_pool, null);

    // Create vertex buffer on GPU
    const vertex_buffer = try gc.dev.createBuffer(&.{
        .size = @sizeOf(@TypeOf(triangle_vertices)),
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer gc.dev.destroyBuffer(vertex_buffer, null);

    // Allocate and bind memory for vertex buffer
    const buffer_memory_requirements = gc.dev.getBufferMemoryRequirements(vertex_buffer);
    const vertex_buffer_memory = try gc.allocate(buffer_memory_requirements, .{ .device_local_bit = true });
    defer gc.dev.freeMemory(vertex_buffer_memory, null);
    try gc.dev.bindBufferMemory(vertex_buffer, vertex_buffer_memory, 0);

    // Upload vertex data to GPU
    try uploadVertexData(&gc, cmd_pool, vertex_buffer);

    // Create command buffers for rendering (one per swapchain image)
    var cmd_buffers = try createRenderCmdBuffers(
        &gc,
        cmd_pool,
        allocator,
        vertex_buffer,
        swapchain.extent,
        graphics_pipeline,
        swapchain,
    );
    defer destroyCmdBuffers(&gc, cmd_pool, allocator, cmd_buffers);

    // Main render loop
    while (app.shouldClose()) {
        if (app.handle() == false) continue; // Resize + Skip loop when mini

        // Get command buffer for current swapchain image
        const curr_cmd_buffer = cmd_buffers[swapchain.image_index];

        // Present the rendered frame
        const present_result = swapchain.present(curr_cmd_buffer) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| return narrow,
        };

        // Check if swapchain needs recreation (window resize, etc.)
        if (present_result == .suboptimal or
            app.extend.width != @as(u32, @intCast(app.curr_width)) or
            app.extend.height != @as(u32, @intCast(app.curr_height)))
        {
            app.extend.width = @intCast(app.curr_width);
            app.extend.height = @intCast(app.curr_height);
            try swapchain.recreate(app.extend);

            // Recreate command buffers for new swapchain
            destroyCmdBuffers(&gc, cmd_pool, allocator, cmd_buffers);
            cmd_buffers = try createRenderCmdBuffers(
                &gc,
                cmd_pool,
                allocator,
                vertex_buffer,
                swapchain.extent,
                graphics_pipeline,
                swapchain,
            );
        }

        app.pollEvents();
    }

    // Wait for all operations to complete before cleanup
    try swapchain.waitForAllFences();
    try gc.dev.deviceWaitIdle();
}
