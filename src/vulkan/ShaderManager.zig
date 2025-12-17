const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const Context = @import("Context.zig").Context;
const RenderType = @import("../config.zig").RenderType;
const ShaderLayout = @import("../config.zig").ShaderLayout;
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const LoadedShader = @import("../core/ShaderCompiler.zig").LoadedShader;
const check = @import("error.zig").check;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const ShaderStage = @import("ShaderObject.zig").ShaderStage;
const ztracy = @import("ztracy");

pub const ShaderManager = struct {
    alloc: Allocator,
    descLayout: vk.VkDescriptorSetLayout,
    gpi: vk.VkDevice,
    shaders: CreateMapArray(ShaderObject, config.SHADER_MAX, u32, config.SHADER_MAX, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !ShaderManager {
        return .{
            .alloc = alloc,
            .descLayout = resourceManager.descLayout,
            .gpi = context.gpi,
        };
    }

    pub fn createShaders(self: *ShaderManager, loadedShaders: []LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            const shaderObj = try ShaderObject.init(self.gpi, loadedShader, self.descLayout);
            const id = loadedShader.shaderConfig.id;

            if (self.shaders.isKeyUsed(id) == true) {
                self.shaders.getPtr(id).*.deinit(self.gpi);
                std.debug.print("Shader {} Updated\n", .{id});
            } else std.debug.print("Shader {} Created\n", .{id});
            self.shaders.set(id, shaderObj);
        }
    }

    pub fn getShaders(self: *ShaderManager, shaderIds: []const u8) [8]ShaderObject {
        var shaders: [8]ShaderObject = undefined;
        for (0..shaderIds.len) |i| {
            shaders[i] = self.shaders.get(shaderIds[i]);
        }
        return shaders;
    }

    pub fn deinit(self: *ShaderManager) void {
        const gpi = self.gpi;
        for (self.shaders.getElements()) |*shader| {
            shader.deinit(gpi);
        }
    }
};
