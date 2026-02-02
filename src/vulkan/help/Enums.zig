const vk = @import("../../modules/vk.zig").c;

pub const UpdateType = enum {
    Overwrite, // Resource once in Memory, updates blocked
    PerFrame, // Resource Created for Every Frame in Flight, updates done per Frame via Staging Buffer
    // Async, // Resource Created Twice, Cycling Between Front and Back Representations to start next batch update when previous update is done
};

pub const TextureType = enum {
    Color,
    Depth,
    Stencil,
};

pub const MemUsage = enum {
    Gpu,
    CpuWrite,
    CpuRead,
};

pub const BufferType = enum {
    Storage,
    Uniform,
    Index,
    Vertex,
    Staging,
    Indirect,
};

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
    Clear = vk.VK_PIPELINE_STAGE_2_CLEAR_BIT,
    ComputeShader = vk.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
    DrawIndirect = vk.VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT,
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
    comp,
    vert,
    tessControl,
    tessEval,
    geometry,
    task,
    meshWithTask,
    meshNoTask,
    frag,
};
