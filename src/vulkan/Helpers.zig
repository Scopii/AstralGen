const vk = @import("../modules/vk.zig").c;
const std = @import("std");

pub const TextureType = enum { Color, Depth, Stencil };

pub const MemUsage = enum { Gpu, CpuWrite, CpuRead };

pub const BufferType = enum { Storage, Uniform, Index, Vertex, Staging };

pub const ImageLayout = enum(vk.VkImageLayout) {
    Undefined = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    General = vk.VK_IMAGE_LAYOUT_GENERAL, // for Storage Images / Compute Writes
    Attachment = vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL, // Replaces All Attachments (Outputs)
    ReadOnly = vk.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL, // Replaces All AttachmentReads (Inputs)
    TransferSrc = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    TransferDst = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    PresentSrc = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    //more exist
};

pub const PipeStage = enum(vk.VkPipelineStageFlagBits2) { //( SHOULD BE CORRECT ORDER)
    TopOfPipe = vk.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
    ComputeShader = vk.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
    VertShader = vk.VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT,
    TaskShader = vk.VK_PIPELINE_STAGE_2_TASK_SHADER_BIT_EXT,
    MeshShader = vk.VK_PIPELINE_STAGE_2_MESH_SHADER_BIT_EXT,
    FragShader = vk.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
    EarlyFragTest = vk.VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
    ColorAtt = vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
    LatFragTest = vk.VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
    AllGraphics = vk.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
    Transfer = vk.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
    AllCmds = vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
    BotOfPipe = vk.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
    //.. more exist
};

pub const PipeAccess = enum(vk.VkAccessFlagBits2) {
    None = 0,
    ShaderRead = vk.VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
    ShaderWrite = vk.VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
    ShaderReadWrite = vk.VK_ACCESS_2_SHADER_STORAGE_READ_BIT | vk.VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,

    IndirectRead = vk.VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT,

    ColorAttWrite = vk.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
    ColorAttRead = vk.VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT,
    ColorAttReadWrite = vk.VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT | vk.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,

    DepthStencilRead = vk.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
    DepthStencilWrite = vk.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,

    TransferRead = vk.VK_ACCESS_2_TRANSFER_READ_BIT,
    TransferWrite = vk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
    TransferReadWrite = vk.VK_ACCESS_2_TRANSFER_READ_BIT | vk.VK_ACCESS_2_TRANSFER_WRITE_BIT,

    MemoryRead = vk.VK_ACCESS_2_MEMORY_READ_BIT,
    MemoryWrite = vk.VK_ACCESS_2_MEMORY_WRITE_BIT,
    MemoryReadWrite = vk.VK_ACCESS_2_MEMORY_READ_BIT | vk.VK_ACCESS_2_MEMORY_WRITE_BIT,
    //.. more exist
};

pub const ShaderStage = enum(vk.VkShaderStageFlagBits) {
    compute,
    vert,
    tessControl,
    tessEval,
    geometry,
    task,
    mesh,
    meshNoTask,
    frag,
};

pub fn getShaderBit(stageEnum: ShaderStage) vk.VkShaderStageFlagBits {
    return switch (stageEnum) {
        .compute => vk.VK_SHADER_STAGE_COMPUTE_BIT,
        .vert => vk.VK_SHADER_STAGE_VERTEX_BIT,
        .tessControl => vk.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
        .tessEval => vk.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
        .geometry => vk.VK_SHADER_STAGE_GEOMETRY_BIT,
        .task => vk.VK_SHADER_STAGE_TASK_BIT_EXT,
        .mesh => vk.VK_SHADER_STAGE_MESH_BIT_EXT,
        .meshNoTask => vk.VK_SHADER_STAGE_MESH_BIT_EXT,
        .frag => vk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };
}

pub fn check(result: vk.VkResult, comptime msg: []const u8) !void {
    if (result == vk.VK_SUCCESS) return;
    try errorHandle(result, msg);
}

fn errorHandle(result: vk.VkResult, comptime msg: []const u8) !void {
    switch (result) {
        vk.VK_TIMEOUT => std.log.err("{s} - Timeout", .{msg}),
        vk.VK_ERROR_OUT_OF_HOST_MEMORY => std.log.err("{s} - Out of Memory", .{msg}),
        vk.VK_ERROR_OUT_OF_DEVICE_MEMORY => std.log.err("{s} - Out of GPU Memory", .{msg}),
        vk.VK_ERROR_INITIALIZATION_FAILED => std.log.err("{s} - Initialization failed", .{msg}),
        vk.VK_ERROR_DEVICE_LOST => std.log.err("{s} - GPU lost", .{msg}),
        vk.VK_ERROR_MEMORY_MAP_FAILED => std.log.err("{s} - Memory Map Failed", .{msg}),
        else => std.log.err("{s} - Reason: {}", .{ msg, result }),
    }
    return error.VulkanError;
}

pub fn Handle(comptime _: type) type {
    return packed struct {
        id: u32,
        // pub inline fn raw(self: @This()) u32 {
        //     return self.id;
        // }
    };
}

// pub const TexId = Handle(struct {}); 
// pub const BufferId = Handle(struct {}); 
// pub const ShaderId = Handle(struct {}); 
// pub const WindowId = Handle(struct {}); 
// pub const SwapchainId = Handle(struct {}); 

// pub fn setDebugName(self: *Context, handle: u64, type_: vk.VkObjectType, name: []const u8) void {
//     if (appCon.DEBUG_MODE) {
//         // ... call vkSetDebugUtilsObjectNameEXT ...
//     }
// }

// if (info.name) |n| {
//     ctx.setDebugName(@intFromEnum(handle), .VK_OBJECT_TYPE_IMAGE, n);
// }
