const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const RenderType = @import("../config.zig").RenderType;
const PushConstants = @import("ShaderManager.zig").PushConstants;
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

    pub fn init(
        alloc: Allocator,
        gpi: c.VkDevice,
        shader: config.Shader,
        nextStage: c.VkShaderStageFlagBits,
        descLayout: c.VkDescriptorSetLayout,
        renderType: RenderType,
    ) !ShaderObject {
        const stage = shader.stage;
        const spvFile = shader.spvFile;

        const rootPath = try resolveProjectRoot(alloc, config.rootPath);
        defer alloc.free(rootPath);
        const spvPath = std.fs.path.join(alloc, &[_][]const u8{ rootPath, config.sprvPath, spvFile }) catch |err| {
            std.debug.print("ShaderObject spv Path could not be resolved {}\n", .{err});
            return err;
        };
        defer alloc.free(spvPath);

        const spvData = try loadShader(alloc, spvPath);
        defer alloc.free(spvData);

        // Set flags based on shader stage
        var flags: c.VkShaderCreateFlagsEXT = 0;
        if (stage == .mesh and renderType == .meshPass) {
            flags |= c.VK_SHADER_CREATE_NO_TASK_SHADER_BIT_EXT; // because task shader isnt used YET
        }

        const shaderInf = c.VkShaderCreateInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .pNext = null,
            .flags = if (renderType == .computePass) 0 else flags,
            .stage = @intFromEnum(stage),
            .nextStage = nextStage,
            .codeType = c.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = spvData.len,
            .pCode = spvData.ptr,
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
            .stage = stage,
        };
    }

    pub fn deinit(self: ShaderObject, gpi: c.VkDevice) void {
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
