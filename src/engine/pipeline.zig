const vk = @import("vulkan");
const Context = @import("context.zig").Context;
const Vertex = @import("resources/vertex.zig").Vertex;

// Embed compiled shaders as binary data aligned for GPU usage
const vert_spv align(@alignOf(u32)) = @embedFile("vert_shdr").*;
const frag_spv align(@alignOf(u32)) = @embedFile("frag_shdr").*;

/// Creates a graphics pipeline for dynamic rendering (no render pass needed!)
pub fn createPipeline(
    gc: *const Context,
    layout: vk.PipelineLayout,
    color_format: vk.Format, // Surface format instead of render pass
) !vk.Pipeline {
    const vert = try gc.dev.createShaderModule(&.{
        .code_size = vert_spv.len,
        .p_code = @ptrCast(&vert_spv),
    }, null);
    defer gc.dev.destroyShaderModule(vert, null);

    const frag = try gc.dev.createShaderModule(&.{
        .code_size = frag_spv.len,
        .p_code = @ptrCast(&frag_spv),
    }, null);
    defer gc.dev.destroyShaderModule(frag, null);

    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag,
            .p_name = "main",
        },
    };

    // Vertex input configuration
    const vertex_input_info = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&Vertex.binding_description),
        .vertex_attribute_description_count = Vertex.attribute_descriptions.len,
        .p_vertex_attribute_descriptions = &Vertex.attribute_descriptions,
    };

    // Input assembly (how vertices form primitives)
    const input_assembly_info = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list, // Every 3 vertices form a triangle
        .primitive_restart_enable = vk.FALSE,
    };

    // Viewport and scissor (set dynamically)
    const viewport_state_info = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = undefined, // Dynamic
        .scissor_count = 1,
        .p_scissors = undefined, // Dynamic
    };

    // Rasterization configuration
    const rasterization_info = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill, // Fill triangles
        .cull_mode = .{ .back_bit = true }, // Cull back faces
        .front_face = .clockwise, // Front face winding order
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1.0,
    };

    // Multisampling (disabled for simplicity)
    const multisample_info = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = vk.FALSE,
        .min_sample_shading = 1.0,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    // Color blending for single attachment
    const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
        .blend_enable = vk.FALSE, // No blending
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const color_blend_info = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_blend_attachment),
        .blend_constants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    // Dynamic state (viewport and scissor can change without recreating pipeline)
    const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };
    const dynamic_state_info = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynamic_states.len,
        .p_dynamic_states = &dynamic_states,
    };

    // Dynamic rendering configuration (replaces render pass)
    const color_formats = [_]vk.Format{color_format};
    var pipeline_rendering_info = vk.PipelineRenderingCreateInfo{
        .s_type = .pipeline_rendering_create_info,
        .p_next = null,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachment_formats = &color_formats,
        .depth_attachment_format = .undefined, // No depth buffer
        .stencil_attachment_format = .undefined, // No stencil buffer
    };

    // Complete pipeline configuration
    const pipeline_create_info = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .p_next = &pipeline_rendering_info, // Link dynamic rendering info
        .stage_count = 2,
        .p_stages = &shader_stages,
        .p_vertex_input_state = &vertex_input_info,
        .p_input_assembly_state = &input_assembly_info,
        .p_tessellation_state = null,
        .p_viewport_state = &viewport_state_info,
        .p_rasterization_state = &rasterization_info,
        .p_multisample_state = &multisample_info,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &color_blend_info,
        .p_dynamic_state = &dynamic_state_info,
        .layout = layout,
        .render_pass = .null_handle, // No render pass needed!
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try gc.dev.createGraphicsPipelines(
        .null_handle,
        1,
        @ptrCast(&pipeline_create_info),
        null,
        @ptrCast(&pipeline),
    );
    return pipeline;
}
