const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const PipelineType = @import("ShaderPipeline.zig").PipelineType;
const ShaderInfo = @import("ShaderPipeline.zig").ShaderInfo;
const ComputePushConstants = @import("ShaderPipeline.zig").ComputePushConstants;
const check = @import("error.zig").check;
const resolveProjectRoot = @import("../core/FileManager.zig").resolveProjectRoot;

pub const ShaderObject = struct {
    handle: c.VkShaderEXT,
    stage: c.VkShaderStageFlagBits,

    pub fn init(
        gpi: c.VkDevice,
        pipeInf: ShaderInfo,
        nextStage: c.VkShaderStageFlagBits,
        alloc: Allocator,
        descLayout: c.VkDescriptorSetLayout,
        pipeType: PipelineType,
    ) !ShaderObject {
        const stage = pipeInf.stage;
        const spvFile = pipeInf.spvFile;

        const rootPath = try resolveProjectRoot(alloc, config.rootPath);
        defer alloc.free(rootPath);
        const spvFilePath = std.fs.path.join(alloc, &[_][]const u8{ rootPath, config.sprvPath, spvFile }) catch |err| {
            std.debug.print("ShaderPipeline: spvFilePath could not be resolved {}\n", .{err});
            return err;
        };
        defer alloc.free(spvFilePath);

        const spvData = try loadShader(alloc, spvFilePath);
        defer alloc.free(spvData);

        // Set flags based on shader stage
        var flags: c.VkShaderCreateFlagsEXT = 0;
        if (stage == c.VK_SHADER_STAGE_MESH_BIT_EXT and pipeType == .mesh) {
            flags |= c.VK_SHADER_CREATE_NO_TASK_SHADER_BIT_EXT; // because task shader isnt used YET
        }

        const shaderCreateInfo = c.VkShaderCreateInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .pNext = null,
            .flags = if (pipeType == .compute) 0 else flags,
            .stage = stage,
            .nextStage = nextStage,
            .codeType = c.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = spvData.len,
            .pCode = spvData.ptr,
            .pName = "main",
            .setLayoutCount = if (descLayout != null) @as(u32, 1) else 0,
            .pSetLayouts = if (descLayout != null) &descLayout else null,
            .pushConstantRangeCount = if (pipeType == .compute) 1 else 0,
            .pPushConstantRanges = if (pipeType == .compute) &c.VkPushConstantRange{
                .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
                .offset = 0,
                .size = @sizeOf(ComputePushConstants),
            } else null,
            .pSpecializationInfo = null,
        };

        var shader: c.VkShaderEXT = undefined;
        try check(c.pfn_vkCreateShadersEXT.?(gpi, 1, &shaderCreateInfo, null, &shader), "Failed to create graphics shader object");

        return .{
            .handle = shader,
            .stage = stage,
        };
    }

    pub fn deinit(self: ShaderObject, gpi: c.VkDevice) void {
        c.pfn_vkDestroyShaderEXT.?(gpi, self.handle, null);
    }
};

fn loadShader(alloc: Allocator, spvPath: []const u8) ![]align(@alignOf(u32)) u8 {
    std.debug.print("Loading shader: {s}\n", .{spvPath});
    const file = std.fs.cwd().openFile(spvPath, .{}) catch |err| {
        std.debug.print("Failed to load shader: {s}\n", .{spvPath});
        return err;
    };
    defer file.close();

    const size = try file.getEndPos();
    const data = try alloc.alignedAlloc(u8, @alignOf(u32), size);
    _ = try file.readAll(data);
    return data;
}
