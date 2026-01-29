const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const ShaderId = @import("../../core/ShaderCompiler.zig").ShaderInf.ShaderId;
const LoadedShader = @import("../../core/ShaderCompiler.zig").LoadedShader;
const shaderCon = @import("../../configs/shaderConfig.zig");
const ResourceMan = @import("ResourceMan.zig").ResourceMan;
const Shader = @import("../types/base/Shader.zig").Shader;
const Pass = @import("../types/base/Pass.zig").Pass;
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const std = @import("std");

pub const ShaderMan = struct {
    alloc: Allocator,
    descLayout: vk.VkDescriptorSetLayout,
    gpi: vk.VkDevice,
    shaders: CreateMapArray(Shader, shaderCon.SHADER_MAX, u8, shaderCon.SHADER_MAX, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceMan) !ShaderMan {
        return .{
            .alloc = alloc,
            .descLayout = resourceManager.descMan.descLayout,
            .gpi = context.gpi,
        };
    }

    pub fn deinit(self: *ShaderMan) void {
        const gpi = self.gpi;
        for (self.shaders.getElements()) |*shader| {
            shader.deinit(gpi);
        }
    }

    pub fn isShaderIdUsed(self: *ShaderMan, shaderId: u8) bool {
        return self.shaders.isKeyUsed(shaderId);
    }

    pub fn createShaders(self: *ShaderMan, loadedShaders: []const LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            const shaderObj = try Shader.init(self.gpi, loadedShader, self.descLayout);
            const id = loadedShader.shaderInf.id.val;
            const name = loadedShader.shaderInf.spvFile;

            if (self.shaders.isKeyUsed(id) == true) {
                self.shaders.getPtr(id).*.deinit(self.gpi);
                std.debug.print("Shader {} updated ({s})\n", .{ id, name });
            } else std.debug.print("Shader {} created ({s})\n", .{ id, name });
            self.shaders.set(id, shaderObj);
        }
    }

    pub fn getShaders(self: *ShaderMan, shaderIds: []const ShaderId) [8]Shader {
        var shaders: [8]Shader = undefined;
        for (0..shaderIds.len) |i| {
            shaders[i] = self.shaders.get(shaderIds[i].val);
        }
        return shaders;
    }

    pub fn isPassValid(self: *ShaderMan, pass: Pass) bool {
        const shaders = self.getShaders(pass.shaderIds)[0..pass.shaderIds.len];

        const layoutType = checkShaderLayout(shaders) catch |err| {
            std.debug.print("Pass {} Shader Layout invalid\n", .{err});
            return false;
        };

        switch (pass.typ) {
            .compute => if (layoutType == .computePass) return true,
            .classic => |classic| {
                switch (classic.classicTyp) {
                    .graphics => if (layoutType == .graphicsPass) return true,
                    .taskMesh => if (layoutType == .meshPass or layoutType == .taskMeshPass) return true,
                }
            },
        }
        std.debug.print("Error: ShaderLayout {s} does not fit Pass\n", .{
            @tagName(layoutType),
        });
        return false;
    }
};

fn checkShaderLayout(shaders: []const Shader) !enum { computePass, graphicsPass, meshPass, taskMeshPass, vertexPass } {
    var shdr: [9]u8 = .{0} ** 9;
    var prevIndex: i8 = -1;

    for (shaders) |shader| {
        const curIndex: i8 = switch (shader.stage) {
            .comp => 0,
            .vert => 1,
            .tessControl => 2,
            .tessEval => 3,
            .geometry => 4,
            .task => 5,
            .meshWithTask => 6,
            .meshNoTask => 6,
            .frag => 7,
        };
        prevIndex = curIndex;
        shdr[@intCast(curIndex)] += 1;
    }
    switch (shaders.len) {
        1 => if (shdr[0] == 1) return .computePass else if (shdr[1] == 1) return .vertexPass,
        2 => if (shdr[6] == 1 and shdr[7] == 1) return .meshPass,
        3 => if (shdr[5] == 1 and shdr[6] == 1 and shdr[7] == 1) return .taskMeshPass,
        else => {},
    }
    if (shdr[1] == 1 and shdr[2] <= 1 and shdr[3] <= 1 and shdr[4] <= 1 and shdr[5] == 0 and shdr[6] == 0 and shdr[7] == 1) return .graphicsPass;
    if (shdr[2] != shdr[3]) return error.ShaderLayoutTessellationMismatch;
    return error.ShaderLayoutInvalid;
}
