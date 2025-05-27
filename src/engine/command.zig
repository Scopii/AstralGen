const std = @import("std");
const vk = @import("vulkan");
const Context = @import("context.zig").Context;
const Swapchain = @import("swapchain.zig").Swapchain;

// Mesh Data
const triangle_vertices = @import("mesh/triangle.zig").triangle_vertices;

// Re-Formats
const Allocator = std.mem.Allocator;

/// Creates command buffers that record rendering commands using dynamic rendering
pub fn createRenderCmdBuffers(
    gc: *const Context,
    cmd_pool: vk.CommandPool,
    allocator: Allocator,
    vertex_buffer: vk.Buffer,
    render_extent: vk.Extent2D,
    pipeline: vk.Pipeline,
    swapchain: Swapchain,
) ![]vk.CommandBuffer {

    // Allocate one command buffer per swapchain image
    const cmd_buffers = try allocator.alloc(vk.CommandBuffer, swapchain.swap_images.len);
    errdefer allocator.free(cmd_buffers);

    try gc.dev.allocateCommandBuffers(&.{
        .command_pool = cmd_pool,
        .level = .primary,
        .command_buffer_count = @intCast(cmd_buffers.len),
    }, cmd_buffers.ptr);
    errdefer gc.dev.freeCommandBuffers(cmd_pool, @intCast(cmd_buffers.len), cmd_buffers.ptr);

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
    for (cmd_buffers, swapchain.swap_images) |cmd_buffer, swap_image| {
        try gc.dev.beginCommandBuffer(cmd_buffer, &.{});

        // Set dynamic state (viewport and scissor)
        gc.dev.cmdSetViewport(cmd_buffer, 0, 1, @ptrCast(&viewport));
        gc.dev.cmdSetScissor(cmd_buffer, 0, 1, @ptrCast(&scissor_rect));

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
        gc.dev.cmdBeginRendering(cmd_buffer, &rendering_info);

        // Bind graphics pipeline and draw triangle
        gc.dev.cmdBindPipeline(cmd_buffer, .graphics, pipeline);
        const vertex_buffer_offset = [_]vk.DeviceSize{0};
        gc.dev.cmdBindVertexBuffers(cmd_buffer, 0, 1, @ptrCast(&vertex_buffer), &vertex_buffer_offset);
        gc.dev.cmdDraw(cmd_buffer, triangle_vertices.len, 1, 0, 0);

        // End dynamic rendering
        gc.dev.cmdEndRendering(cmd_buffer);
        try gc.dev.endCommandBuffer(cmd_buffer);
    }
    return cmd_buffers;
}

pub fn destroyCmdBuffers(gc: *const Context, cmd_pool: vk.CommandPool, allocator: Allocator, cmd_buffers: []vk.CommandBuffer) void {
    gc.dev.freeCommandBuffers(cmd_pool, @truncate(cmd_buffers.len), cmd_buffers.ptr);
    allocator.free(cmd_buffers);
}
