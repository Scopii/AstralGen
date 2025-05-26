// Imports
const std = @import("std");
const vk = @import("vulkan");
const c = @import("c.zig");
const GraphicsContext = @import("engine/graphics_context.zig").GraphicsContext;
const Swapchain = @import("engine/swapchain.zig").Swapchain;
const createPipeline = @import("engine/pipeline.zig").createPipeline;
const createRenderCommandBuffers = @import("engine/command.zig").createRenderCommandBuffers;
const destroyCommandBuffers = @import("engine/command.zig").destroyCommandBuffers;
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

    // Initialize Vulkan context (instance, device, queues, etc.)
    const graphics_context = try GraphicsContext.init(allocator, "AstralGen", app.window);
    defer graphics_context.deinit();

    std.log.debug("Using GPU: {s}", .{graphics_context.deviceName()});

    // Create swapchain for presenting images to the window
    var swapchain = try Swapchain.init(&graphics_context, allocator, app.extend);
    defer swapchain.deinit();

    // Create pipeline layout (describes shader resources - none in this simple example)
    const pipeline_layout = try graphics_context.dev.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    defer graphics_context.dev.destroyPipelineLayout(pipeline_layout, null);

    // Create graphics pipeline using dynamic rendering (no render pass needed!)
    const graphics_pipeline = try createPipeline(&graphics_context, pipeline_layout, swapchain.surface_format.format);
    defer graphics_context.dev.destroyPipeline(graphics_pipeline, null);

    // Create command pool for allocating command buffers
    const command_pool = try graphics_context.dev.createCommandPool(&.{
        .queue_family_index = graphics_context.graphics_queue.family,
    }, null);
    defer graphics_context.dev.destroyCommandPool(command_pool, null);

    // Create vertex buffer on GPU
    const vertex_buffer = try graphics_context.dev.createBuffer(&.{
        .size = @sizeOf(@TypeOf(triangle_vertices)),
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer graphics_context.dev.destroyBuffer(vertex_buffer, null);

    // Allocate and bind memory for vertex buffer
    const buffer_memory_requirements = graphics_context.dev.getBufferMemoryRequirements(vertex_buffer);
    const vertex_buffer_memory = try graphics_context.allocate(buffer_memory_requirements, .{ .device_local_bit = true });
    defer graphics_context.dev.freeMemory(vertex_buffer_memory, null);
    try graphics_context.dev.bindBufferMemory(vertex_buffer, vertex_buffer_memory, 0);

    // Upload vertex data to GPU
    try uploadVertexData(&graphics_context, command_pool, vertex_buffer);

    // Create command buffers for rendering (one per swapchain image)
    var command_buffers = try createRenderCommandBuffers(
        &graphics_context,
        command_pool,
        allocator,
        vertex_buffer,
        swapchain.extent,
        graphics_pipeline,
        swapchain,
    );
    defer destroyCommandBuffers(&graphics_context, command_pool, allocator, command_buffers);

    // Main render loop
    while (app.shouldClose()) {
        if (app.handle() == false) continue; // Resize + Skip loop when mini

        // Get command buffer for current swapchain image
        const current_command_buffer = command_buffers[swapchain.image_index];

        // Present the rendered frame
        const present_result = swapchain.present(current_command_buffer) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| return narrow,
        };

        // Check if swapchain needs recreation (window resize, etc.)
        if (present_result == .suboptimal or
            app.extend.width != @as(u32, @intCast(app.window_width)) or
            app.extend.height != @as(u32, @intCast(app.window_height)))
        {
            app.extend.width = @intCast(app.window_width);
            app.extend.height = @intCast(app.window_height);
            try swapchain.recreate(app.extend);

            // Recreate command buffers for new swapchain
            destroyCommandBuffers(&graphics_context, command_pool, allocator, command_buffers);
            command_buffers = try createRenderCommandBuffers(
                &graphics_context,
                command_pool,
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
    try graphics_context.dev.deviceWaitIdle();
}
