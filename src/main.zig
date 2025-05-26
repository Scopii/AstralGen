// Imports
const std = @import("std");
const vk = @import("vulkan");
const c = @import("c.zig");
const GraphicsContext = @import("engine/graphics_context.zig").GraphicsContext;
const Swapchain = @import("engine/swapchain.zig").Swapchain;
const Vertex = @import("engine/resources/vertex.zig").Vertex;
const createPipeline = @import("engine/pipeline.zig").createPipeline;
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
    while (c.glfwWindowShouldClose(app.window) == c.GLFW_FALSE) {
        // Get current window size (might have changed due to resize)
        var window_width: c_int = undefined;
        var window_height: c_int = undefined;
        c.glfwGetFramebufferSize(app.window, &window_width, &window_height);

        // Handle window minimization
        if (window_width == 0 or window_height == 0) {
            c.glfwPollEvents();
            continue;
        }

        // Get command buffer for current swapchain image
        const current_command_buffer = command_buffers[swapchain.image_index];

        // Present the rendered frame
        const present_result = swapchain.present(current_command_buffer) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| return narrow,
        };

        // Check if swapchain needs recreation (window resize, etc.)
        if (present_result == .suboptimal or
            app.extend.width != @as(u32, @intCast(window_width)) or
            app.extend.height != @as(u32, @intCast(window_height)))
        {
            app.extend.width = @intCast(window_width);
            app.extend.height = @intCast(window_height);
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

        app.pollEvens();
    }

    // Wait for all operations to complete before cleanup
    try swapchain.waitForAllFences();
    try graphics_context.dev.deviceWaitIdle();
}

/// Creates command buffers that record rendering commands using dynamic rendering
fn createRenderCommandBuffers(
    graphics_context: *const GraphicsContext,
    command_pool: vk.CommandPool,
    allocator: Allocator,
    vertex_buffer: vk.Buffer,
    render_extent: vk.Extent2D,
    pipeline: vk.Pipeline,
    swapchain: Swapchain,
) ![]vk.CommandBuffer {

    // Allocate one command buffer per swapchain image
    const command_buffers = try allocator.alloc(vk.CommandBuffer, swapchain.swap_images.len);
    errdefer allocator.free(command_buffers);

    try graphics_context.dev.allocateCommandBuffers(&.{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = @intCast(command_buffers.len),
    }, command_buffers.ptr);
    errdefer graphics_context.dev.freeCommandBuffers(command_pool, @intCast(command_buffers.len), command_buffers.ptr);

    // Clear color (black background)
    const clear_color = vk.ClearValue{
        .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 1.0 } },
    };

    // Viewport covers entire render area
    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(render_extent.width),
        .height = @floatFromInt(render_extent.height),
        .min_depth = 0.0,
        .max_depth = 1.0,
    };

    // Scissor rectangle (same as viewport in this case)
    const scissor_rect = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = render_extent,
    };

    // Record rendering commands for each swapchain image
    for (command_buffers, swapchain.swap_images) |cmd_buffer, swap_image| {
        try graphics_context.dev.beginCommandBuffer(cmd_buffer, &.{});

        // Set dynamic state (viewport and scissor)
        graphics_context.dev.cmdSetViewport(cmd_buffer, 0, 1, @ptrCast(&viewport));
        graphics_context.dev.cmdSetScissor(cmd_buffer, 0, 1, @ptrCast(&scissor_rect));

        // Configure color attachment for dynamic rendering
        const color_attachment_info = vk.RenderingAttachmentInfo{
            .s_type = .rendering_attachment_info,
            .p_next = null,
            .image_view = swap_image.view,
            .image_layout = .color_attachment_optimal,
            .resolve_mode = .{},
            .resolve_image_view = .null_handle,
            .resolve_image_layout = .undefined,
            .load_op = .clear, // Clear the image
            .store_op = .store, // Store the result
            .clear_value = clear_color,
        };

        // Dynamic rendering info (replaces render pass)
        const rendering_info = vk.RenderingInfo{
            .s_type = .rendering_info,
            .p_next = null,
            .flags = .{},
            .render_area = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = render_extent,
            },
            .layer_count = 1,
            .view_mask = 0,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(&color_attachment_info),
            .p_depth_attachment = null,
            .p_stencil_attachment = null,
        };

        // Begin dynamic rendering
        graphics_context.dev.cmdBeginRendering(cmd_buffer, &rendering_info);

        // Bind graphics pipeline and draw triangle
        graphics_context.dev.cmdBindPipeline(cmd_buffer, .graphics, pipeline);
        const vertex_buffer_offset = [_]vk.DeviceSize{0};
        graphics_context.dev.cmdBindVertexBuffers(cmd_buffer, 0, 1, @ptrCast(&vertex_buffer), &vertex_buffer_offset);
        graphics_context.dev.cmdDraw(cmd_buffer, triangle_vertices.len, 1, 0, 0);

        // End dynamic rendering
        graphics_context.dev.cmdEndRendering(cmd_buffer);
        try graphics_context.dev.endCommandBuffer(cmd_buffer);
    }

    return command_buffers;
}

/// Uploads vertex data from CPU to GPU memory
fn uploadVertexData(graphics_context: *const GraphicsContext, command_pool: vk.CommandPool, destination_buffer: vk.Buffer) !void {
    // Create staging buffer in host-visible memory
    const staging_buffer = try graphics_context.dev.createBuffer(&.{
        .size = @sizeOf(@TypeOf(triangle_vertices)),
        .usage = .{ .transfer_src_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer graphics_context.dev.destroyBuffer(staging_buffer, null);

    // Allocate host-visible memory for staging buffer
    const staging_memory_requirements = graphics_context.dev.getBufferMemoryRequirements(staging_buffer);
    const staging_memory = try graphics_context.allocate(staging_memory_requirements, .{ .host_visible_bit = true, .host_coherent_bit = true });
    defer graphics_context.dev.freeMemory(staging_memory, null);
    try graphics_context.dev.bindBufferMemory(staging_buffer, staging_memory, 0);

    // Copy vertex data to staging buffer
    {
        const mapped_memory = try graphics_context.dev.mapMemory(staging_memory, 0, vk.WHOLE_SIZE, .{});
        defer graphics_context.dev.unmapMemory(staging_memory);

        const gpu_vertex_data: [*]Vertex = @ptrCast(@alignCast(mapped_memory));
        @memcpy(gpu_vertex_data, triangle_vertices[0..]);
    }

    // Copy from staging buffer to device-local buffer
    try copyBuffer(graphics_context, command_pool, destination_buffer, staging_buffer, @sizeOf(@TypeOf(triangle_vertices)));
}

/// Copies data between two buffers using a command buffer
fn copyBuffer(graphics_context: *const GraphicsContext, command_pool: vk.CommandPool, dst_buffer: vk.Buffer, src_buffer: vk.Buffer, size: vk.DeviceSize) !void {
    // Allocate temporary command buffer
    var temp_command_buffer: vk.CommandBuffer = undefined;
    try graphics_context.dev.allocateCommandBuffers(&.{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&temp_command_buffer));
    defer graphics_context.dev.freeCommandBuffers(command_pool, 1, @ptrCast(&temp_command_buffer));

    const cmd_buffer = GraphicsContext.CommandBuffer.init(temp_command_buffer, graphics_context.dev.wrapper);

    // Record copy command
    try cmd_buffer.beginCommandBuffer(&.{
        .flags = .{ .one_time_submit_bit = true },
    });

    const copy_region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    cmd_buffer.copyBuffer(src_buffer, dst_buffer, 1, @ptrCast(&copy_region));

    try cmd_buffer.endCommandBuffer();

    // Submit and wait for completion
    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = (&cmd_buffer.handle)[0..1],
        .p_wait_dst_stage_mask = undefined,
    };
    try graphics_context.dev.queueSubmit(graphics_context.graphics_queue.handle, 1, @ptrCast(&submit_info), .null_handle);
    try graphics_context.dev.queueWaitIdle(graphics_context.graphics_queue.handle);
}

fn destroyCommandBuffers(graphics_context: *const GraphicsContext, command_pool: vk.CommandPool, allocator: Allocator, command_buffers: []vk.CommandBuffer) void {
    graphics_context.dev.freeCommandBuffers(command_pool, @truncate(command_buffers.len), command_buffers.ptr);
    allocator.free(command_buffers);
}
