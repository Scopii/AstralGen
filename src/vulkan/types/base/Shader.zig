const LoadedShader = @import("../../../core/ShaderCompiler.zig").LoadedShader;
const PushConstants = @import("../res/PushConstants.zig").PushConstants;
const vk = @import("../../../modules/vk.zig").c;
const vhF = @import("../../help/Functions.zig");
const vkFn = @import("../../../modules/vk.zig");
const vhE = @import("../../help/Enums.zig");

pub const Shader = struct {
    handle: vk.VkShaderEXT,
    stage: vhE.ShaderStage,

    pub fn init(gpi: vk.VkDevice, shader: LoadedShader, descLayout: vk.VkDescriptorSetLayout) !Shader {
        const stageEnum = shader.shaderInf.typ;
        const vkStage = vhF.getShaderBit(stageEnum);

        var flags: vk.VkShaderCreateFlagsEXT = 0;
        if (stageEnum == .meshNoTask) flags |= vk.VK_SHADER_CREATE_NO_TASK_SHADER_BIT_EXT;

        const nextStage: vk.VkShaderStageFlagBits = switch (stageEnum) {
            .vert, .mesh, .meshNoTask => vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .task => vk.VK_SHADER_STAGE_MESH_BIT_EXT,
            else => 0,
        };

        const shaderInf = vk.VkShaderCreateInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .flags = flags,
            .stage = vkStage,
            .nextStage = nextStage,
            .codeType = vk.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = shader.data.len,
            .pCode = @ptrCast(shader.data.ptr),
            .pName = "main",
            .setLayoutCount = if (descLayout != null) 1 else 0,
            .pSetLayouts = if (descLayout != null) &descLayout else null,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &vk.VkPushConstantRange{
                .stageFlags = vk.VK_SHADER_STAGE_ALL,
                .offset = 0,
                .size = @sizeOf(PushConstants),
            },
        };
        var handle: vk.VkShaderEXT = undefined;
        try vhF.check(vkFn.vkCreateShadersEXT.?(gpi, 1, &shaderInf, null, &handle), "Shader Creation Failed");

        return .{
            .handle = handle,
            .stage = stageEnum,
        };
    }

    pub fn deinit(self: *Shader, gpi: vk.VkDevice) void {
        vkFn.vkDestroyShaderEXT.?(gpi, self.handle, null);
    }
};
