const LoadedShader = @import("../../../core/ShaderCompiler.zig").LoadedShader;
const DescriptorMan = @import("../../sys/DescriptorMan.zig").DescriptorMan;
const PushData = @import("../../types/res/PushData.zig").PushData;
const SpecData = @import("../../help/Types.zig").SpecData;
const vk = @import("../../../modules/vk.zig").c;
const vhF = @import("../../help/Functions.zig");
const vkFn = @import("../../../modules/vk.zig");
const vhE = @import("../../help/Enums.zig");

pub const Shader = struct {
    handle: vk.VkShaderEXT,
    stage: vhE.ShaderStage,

    pub fn init(gpi: vk.VkDevice, shader: LoadedShader, descMan: *const DescriptorMan) !Shader {
        const stageEnum = shader.shaderInf.typ;
        const vkStage = vhF.getShaderBit(stageEnum);

        var flags: vk.VkShaderCreateFlagsEXT = vk.VK_SHADER_CREATE_DESCRIPTOR_HEAP_BIT_EXT;
        if (stageEnum == .meshNoTask) flags |= vk.VK_SHADER_CREATE_NO_TASK_SHADER_BIT_EXT;

        const nextStage: vk.VkShaderStageFlagBits = switch (stageEnum) {
            .vert, .meshWithTask, .meshNoTask => vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .task => vk.VK_SHADER_STAGE_MESH_BIT_EXT,
            else => 0,
        };

        var entries = [_]vk.VkSpecializationMapEntry{
            .{ .constantID = 0, .offset = @offsetOf(SpecData, "threadX"), .size = @sizeOf(u32) },
            .{ .constantID = 1, .offset = @offsetOf(SpecData, "threadY"), .size = @sizeOf(u32) },
            .{ .constantID = 2, .offset = @offsetOf(SpecData, "threadZ"), .size = @sizeOf(u32) },
        };

        const specData = SpecData{ .threadX = 8, .threadY = 8, .threadZ = 1 };

        const specInf = vk.VkSpecializationInfo{
            .mapEntryCount = entries.len,
            .pMapEntries = &entries,
            .dataSize = @sizeOf(SpecData),
            .pData = &specData,
        };

        const heapMapping = vk.VkDescriptorSetAndBindingMappingEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_AND_BINDING_MAPPING_EXT,
            .descriptorSet = 0,
            .firstBinding = 0,
            .bindingCount = 1,

            .resourceMask = vk.VK_SPIRV_RESOURCE_TYPE_SAMPLED_IMAGE_BIT_EXT |
                vk.VK_SPIRV_RESOURCE_TYPE_READ_WRITE_IMAGE_BIT_EXT |
                vk.VK_SPIRV_RESOURCE_TYPE_UNIFORM_BUFFER_BIT_EXT |
                vk.VK_SPIRV_RESOURCE_TYPE_READ_WRITE_STORAGE_BUFFER_BIT_EXT |
                vk.VK_SPIRV_RESOURCE_TYPE_READ_ONLY_STORAGE_BUFFER_BIT_EXT,

            .source = vk.VK_DESCRIPTOR_MAPPING_SOURCE_HEAP_WITH_CONSTANT_OFFSET_EXT,

            .sourceData = .{
                .constantOffset = .{
                    .heapOffset = @intCast(descMan.startOffset),
                    .heapArrayStride = @intCast(descMan.descStride),
                    .pEmbeddedSampler = null,
                    .samplerHeapOffset = 0,
                    .samplerHeapArrayStride = 0,
                },
            },
        };
        const mappings = [_]vk.VkDescriptorSetAndBindingMappingEXT{heapMapping};

        const mappingInf = vk.VkShaderDescriptorSetAndBindingMappingInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_SHADER_DESCRIPTOR_SET_AND_BINDING_MAPPING_INFO_EXT,
            .mappingCount = mappings.len,
            .pMappings = &mappings,
        };

        const shaderInf = vk.VkShaderCreateInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .pNext = &mappingInf,
            .flags = flags,
            .stage = vkStage,
            .nextStage = nextStage,
            .codeType = vk.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = shader.data.len,
            .pCode = @ptrCast(shader.data.ptr),
            .pName = "main",
            .setLayoutCount = 0,
            .pSetLayouts = null,
            .pushConstantRangeCount = 0,
            .pPushConstantRanges = null,
            .pSpecializationInfo = &specInf,
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
