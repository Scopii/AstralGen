const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const vkFn = @import("../modules/vk.zig");
const PushConstants = @import("resources/DescriptorManager.zig").PushConstants;
const LoadedShader = @import("../core/ShaderCompiler.zig").LoadedShader;
const check = @import("ErrorHelpers.zig").check;

pub const ShaderStage = enum(vk.VkShaderStageFlagBits) {
    compute = vk.VK_SHADER_STAGE_COMPUTE_BIT,
    vertex = vk.VK_SHADER_STAGE_VERTEX_BIT,
    tessControl = vk.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
    tessEval = vk.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
    geometry = vk.VK_SHADER_STAGE_GEOMETRY_BIT,
    task = vk.VK_SHADER_STAGE_TASK_BIT_EXT,
    mesh = vk.VK_SHADER_STAGE_MESH_BIT_EXT,
    frag = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
};

pub const ShaderObject = struct {
    handle: vk.VkShaderEXT,
    stage: ShaderStage,

    pub fn init(gpi: vk.VkDevice, shader: LoadedShader, descLayout: vk.VkDescriptorSetLayout) !ShaderObject {
        const shaderType = shader.shaderConfig.shaderType;

        var flags: vk.VkShaderCreateFlagsEXT = 0;
        if (shaderType == .meshNoTask) flags |= vk.VK_SHADER_CREATE_NO_TASK_SHADER_BIT_EXT;

        const nextStage: vk.VkShaderStageFlagBits = switch (shaderType) {
            .compute => 0,
            .vert => vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            // .tessControl => return error.ShaderStageNotSetup,
            // .tessEval => return error.ShaderStageNotSetup,
            // .geometry => return error.ShaderStageNotSetup,
            .task => vk.VK_SHADER_STAGE_MESH_BIT_EXT,
            .mesh => vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .meshNoTask => vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .frag => 0,
        };

        const actualStage: ShaderStage = switch (shaderType) {
            .compute => .compute,
            .vert => .vertex,
            // tessControl = vk.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
            // tessEval = vk.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
            // geometry = vk.VK_SHADER_STAGE_GEOMETRY_BIT,
            .task => .task,
            .mesh => .mesh,
            .frag => .frag,
            .meshNoTask => .mesh,
        };

        const shaderInf = vk.VkShaderCreateInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .pNext = null,
            .flags = flags,
            .stage = @intFromEnum(actualStage),
            .nextStage = nextStage,
            .codeType = vk.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = shader.data.len,
            .pCode = shader.data.ptr,
            .pName = "main",
            .setLayoutCount = if (descLayout != null) @as(u32, 1) else 0,
            .pSetLayouts = if (descLayout != null) &descLayout else null,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &vk.VkPushConstantRange{
                .stageFlags = vk.VK_SHADER_STAGE_ALL,
                .offset = 0,
                .size = @sizeOf(PushConstants),
            },
            .pSpecializationInfo = null,
        };
        var shaderObj: vk.VkShaderEXT = undefined;
        try check(vkFn.vkCreateShadersEXT.?(gpi, 1, &shaderInf, null, &shaderObj), "Failed to create graphics ShaderObject");

        return .{
            .handle = shaderObj,
            .stage = actualStage,
        };
    }

    pub fn deinit(self: *ShaderObject, gpi: vk.VkDevice) void {
        vkFn.vkDestroyShaderEXT.?(gpi, self.handle, null);
    }
};
