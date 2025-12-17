const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const RenderType = @import("../config.zig").RenderType;
const PushConstants = @import("ShaderManager.zig").PushConstants;
const LoadedShader = @import("../core/ShaderCompiler.zig").LoadedShader;
const check = @import("error.zig").check;
const resolveProjectRoot = @import("../core/ShaderCompiler.zig").resolveProjectRoot;

pub const ShaderStage = enum(c.VkShaderStageFlagBits) {
    compute = c.VK_SHADER_STAGE_COMPUTE_BIT,
    vertex = c.VK_SHADER_STAGE_VERTEX_BIT,
    tessControl = c.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
    tessEval = c.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
    geometry = c.VK_SHADER_STAGE_GEOMETRY_BIT,
    task = c.VK_SHADER_STAGE_TASK_BIT_EXT,
    mesh = c.VK_SHADER_STAGE_MESH_BIT_EXT,
    frag = c.VK_SHADER_STAGE_FRAGMENT_BIT,
};

pub const ShaderObject = struct {
    handle: c.VkShaderEXT,
    stage: ShaderStage,

    pub fn init(gpi: c.VkDevice, shader: LoadedShader, descLayout: c.VkDescriptorSetLayout) !ShaderObject {
        const shaderType = shader.shaderType;
        // Set flags based on shader stage
        var flags: c.VkShaderCreateFlagsEXT = 0;
        if (shaderType == .meshNoTask) flags |= c.VK_SHADER_CREATE_NO_TASK_SHADER_BIT_EXT;

        const nextStage: c.VkShaderStageFlagBits = switch (shaderType) {
            .compute => 0,
            .vert => c.VK_SHADER_STAGE_FRAGMENT_BIT,
            // .tessControl => return error.ShaderStageNotSetup,
            // .tessEval => return error.ShaderStageNotSetup,
            // .geometry => return error.ShaderStageNotSetup,
            .task => c.VK_SHADER_STAGE_MESH_BIT_EXT,
            .mesh => c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .meshNoTask => c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .frag => 0,
        };

        const actualStage: ShaderStage = switch (shaderType) {
            .compute => .compute,
            .vert => .vertex,
            // tessControl = c.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
            // tessEval = c.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
            // geometry = c.VK_SHADER_STAGE_GEOMETRY_BIT,
            .task => .task,
            .mesh => .mesh,
            .frag => .frag,
            .meshNoTask => .mesh,
        };

        const shaderInf = c.VkShaderCreateInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .pNext = null,
            .flags = flags,
            .stage = @intFromEnum(actualStage),
            .nextStage = nextStage,
            .codeType = c.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = shader.data.len,
            .pCode = shader.data.ptr,
            .pName = "main",
            .setLayoutCount = if (descLayout != null) @as(u32, 1) else 0,
            .pSetLayouts = if (descLayout != null) &descLayout else null,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &c.VkPushConstantRange{
                .stageFlags = c.VK_SHADER_STAGE_ALL,
                .offset = 0,
                .size = @sizeOf(PushConstants),
            },
            .pSpecializationInfo = null,
        };
        var shaderObj: c.VkShaderEXT = undefined;
        try check(c.pfn_vkCreateShadersEXT.?(gpi, 1, &shaderInf, null, &shaderObj), "Failed to create graphics ShaderObject");

        return .{
            .handle = shaderObj,
            .stage = actualStage,
        };
    }

    pub fn deinit(self: *ShaderObject, gpi: c.VkDevice) void {
        c.pfn_vkDestroyShaderEXT.?(gpi, self.handle, null);
    }
};

fn loadShader(alloc: Allocator, spvPath: []const u8) ![]align(@alignOf(u32)) u8 {
    std.debug.print("Shader Loaded {s}\n", .{spvPath});
    const file = std.fs.cwd().openFile(spvPath, .{}) catch |err| {
        std.debug.print("Shader Load Failed {s}\n", .{spvPath});
        return err;
    };
    defer file.close();

    const size = try file.getEndPos();
    const data = try alloc.alignedAlloc(u8, @alignOf(u32), size);
    _ = try file.readAll(data);
    return data;
}
