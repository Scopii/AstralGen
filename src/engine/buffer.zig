const std = @import("std");
const vk = @import("vulkan");
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Vertex = @import("resources/vertex.zig").Vertex;

// Mesh Data
const triangle_vertices = @import("mesh/triangle.zig").triangle_vertices;

/// Uploads vertex data from CPU to GPU memory
pub fn uploadVertexData(graphics_context: *const GraphicsContext, command_pool: vk.CommandPool, destination_buffer: vk.Buffer) !void {
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
pub fn copyBuffer(graphics_context: *const GraphicsContext, command_pool: vk.CommandPool, dst_buffer: vk.Buffer, src_buffer: vk.Buffer, size: vk.DeviceSize) !void {
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
