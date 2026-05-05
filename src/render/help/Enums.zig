const vk = @import("../../.modules/vk.zig").c;
const rc = @import("../../.configs/renderConfig.zig");

pub const UpdateType = enum {
    Rarely, // Resource once in Memory, updates create a new Resource
    Often, // Resource Created for Every Frame in Flight, keeps Reference to Subresource if Buffer does not change
    PerFrame, // Resource Created for Every Frame in Flight, Descriptor Reference cycles through Sub-Resources always

    // Async, // Resource Created Twice, Collecting + Cycling Between Front and Back Representations to start next batch update when previous update is done (maybe multiple Frames)

    pub fn getCount(self: UpdateType) u8 {
        return switch (self) {
            .Rarely => 1,
            .Often => rc.MAX_IN_FLIGHT,
            .PerFrame => rc.MAX_IN_FLIGHT,
        };
    }
};

pub const ResizeType = enum {
    Block, // Can never Resize
    Grow, // Keeps growing
    Fit, // Resizes on every update
};

pub const TexTyp = enum {
    Color16,
    Color8,
    Swapchain,
    Depth32,
    Stencil8,

    pub fn getFormat(self: TexTyp) vk.VkFormat {
        return switch (self) {
            .Color16 => vk.VK_FORMAT_R16G16B16A16_SFLOAT,
            .Color8 => vk.VK_FORMAT_R8G8B8A8_UNORM,
            .Swapchain => vk.VK_FORMAT_R8G8B8A8_UNORM,
            .Depth32 => vk.VK_FORMAT_D32_SFLOAT,
            .Stencil8 => vk.VK_FORMAT_S8_UINT,
        };
    }

    pub fn getImageAspectFlags(self: TexTyp) vk.VkImageAspectFlags {
        return switch (self) {
            .Color16, .Color8, .Swapchain => vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .Depth32 => vk.VK_IMAGE_ASPECT_DEPTH_BIT,
            .Stencil8 => vk.VK_IMAGE_ASPECT_STENCIL_BIT,
        };
    }
};

pub const TexDescriptor = enum {
    Storage,
    Sampled,
};

pub const TexDescriptorUsage = enum {
    StorageOnly,
    SampledOnly,
    StorageSampled,
};

pub const TexUsage = packed struct {
    colorAtt: bool = false, // VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
    depthAtt: bool = false, // VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
    storage: bool = false, // VK_IMAGE_USAGE_STORAGE_BIT
    sampled: bool = false, // VK_IMAGE_USAGE_SAMPLED_BIT
    transferSrc: bool = true, // Always?
    transferDst: bool = true, // Always?

    pub fn getImageUse(self: *const TexUsage) vk.VkImageUsageFlags {
        var flags: vk.VkImageUsageFlags = 0;
        if (self.colorAtt) flags |= vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        if (self.depthAtt) flags |= vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
        if (self.storage) flags |= vk.VK_IMAGE_USAGE_STORAGE_BIT;
        if (self.sampled) flags |= vk.VK_IMAGE_USAGE_SAMPLED_BIT;
        if (self.transferSrc) flags |= vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
        if (self.transferDst) flags |= vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        return flags;
    }
};

pub const MemUsage = enum {
    Gpu,
    CpuWrite,
    CpuRead,
};

pub const BufferType = enum {
    Storage,
    Uniform,
    IndexStorage,
    Index,
    VertexStorage,
    Vertex,
    Staging,
    Indirect,
};

pub const ImageLayout = enum(vk.VkImageLayout) {
    Undefined = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    General = vk.VK_IMAGE_LAYOUT_GENERAL, // for Storage Images / Compute Writes
    Attachment = vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL, // Replaces All Attachments (Outputs)
    ReadOnly = vk.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL, // // Any read-only access: sampled, depth read-only, input attachments
    TransferSrc = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    TransferDst = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    PresentSrc = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    //more exist
};

pub const PipeStage = enum(vk.VkPipelineStageFlagBits2) { //( SHOULD BE CORRECT ORDER)
    TopOfPipe = vk.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
    Clear = vk.VK_PIPELINE_STAGE_2_CLEAR_BIT,
    Compute = vk.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
    DrawIndirect = vk.VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT,
    Vertex = vk.VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT,
    VertexInput = vk.VK_PIPELINE_STAGE_2_VERTEX_INPUT_BIT,
    Task = vk.VK_PIPELINE_STAGE_2_TASK_SHADER_BIT_EXT,
    Mesh = vk.VK_PIPELINE_STAGE_2_MESH_SHADER_BIT_EXT,
    Fragment = vk.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
    EarlyFragTest = vk.VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
    ColorAtt = vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
    LatFragTest = vk.VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
    AllGraphics = vk.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
    Transfer = vk.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
    AllCmds = vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
    BotOfPipe = vk.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
    //more exist
};

pub const PipeAccess = enum(vk.VkAccessFlagBits2) {
    None = 0,

    ResourceHeapRead = vk.VK_ACCESS_2_RESOURCE_HEAP_READ_BIT_EXT,
    SamplerHeapRead = vk.VK_ACCESS_2_SAMPLER_HEAP_READ_BIT_EXT,

    ShaderRead = vk.VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
    ShaderWrite = vk.VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
    ShaderReadWrite = vk.VK_ACCESS_2_SHADER_STORAGE_READ_BIT | vk.VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,

    UniformRead = vk.VK_ACCESS_2_UNIFORM_READ_BIT,

    SampledRead = vk.VK_ACCESS_2_SHADER_SAMPLED_READ_BIT,

    IndexRead = vk.VK_ACCESS_2_INDEX_READ_BIT,

    IndirectRead = vk.VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT,

    VertexAttributeRead = vk.VK_ACCESS_2_VERTEX_ATTRIBUTE_READ_BIT,

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
    //more exist
};

pub const ShaderStage = enum {
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
