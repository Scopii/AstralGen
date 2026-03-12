const ShaderId = @import("../ids/shaderId.zig").ShaderId;
const vkE = @import("../vulkan/help/Enums.zig");

pub const ShaderInf = struct {
    id: ShaderId,
    typ: vkE.ShaderStage,
    file: []const u8,
    spvFile: []const u8,

    pub fn init(id: u32, typ: vkE.ShaderStage, file: []const u8, spvFile: []const u8) ShaderInf {
        return .{ .id = .{ .val = id }, .typ = typ, .file = file, .spvFile = spvFile };
    }
};
