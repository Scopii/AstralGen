const PassDefinition = @import("../../render/types/pass/PassDefinition.zig").PassDefinition;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const ResourceRegistryData = @import("ResourceRegistryData.zig").ResourceRegistryData;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

pub const ResourceRegistrySys = struct {
    pub fn init(self: *ResourceRegistryData, alloc: std.mem.Allocator) !void {
        self.passIdMap = std.StringHashMap(PassId).init(alloc);
        try self.passIdMap.ensureTotalCapacity(rc.PASS_MAX);

        self.bufPassIdMap = std.StringHashMap(BufPassId).init(alloc);
        try self.bufPassIdMap.ensureTotalCapacity(rc.BUF_MAX);

        self.texPassIdMap = std.StringHashMap(TexPassId).init(alloc);
        try self.texPassIdMap.ensureTotalCapacity(rc.TEX_MAX);
    }

    pub fn deinit(self: *ResourceRegistryData) void {
        self.passIdMap.deinit();
        self.bufPassIdMap.deinit();
        self.texPassIdMap.deinit();
    }

    pub fn addPassDefinition(resourceRegistry: *ResourceRegistryData, passId: PassId, passDef: PassDefinition) !void {
        try passDef.validate();
        const passName = passDef.name.get();

        if (resourceRegistry.passIdMap.contains(passName) == true) {
            std.debug.print("ERROR: Pass Definition ({s}) already Exists\n", .{passName});
            return error.PassNameAlreadyExists;
        }
        resourceRegistry.passDefinitions.upsert(passId.val(), passDef);
        resourceRegistry.passNames.upsert(passId.val(), try .string(passName));

        const persistentName = resourceRegistry.passNames.getConstPtrByKey(passId.val()).get();
        resourceRegistry.passIdMap.putAssumeCapacity(persistentName, passId);
    }

    pub fn removePassDefinition(resourceRegistry: *ResourceRegistryData, name: []const u8) void {
        if (resourceRegistry.passIdMap.get(name)) |passId| {
            resourceRegistry.passIdMap.remove(name);
            resourceRegistry.passDefinitions.remove(passId.val());
            resourceRegistry.passNames.remove(passId.val());
        }
    }

    pub fn addTextureDefinition(resourceRegistry: *ResourceRegistryData, texPassId: TexPassId, newName: []const u8, newTexDesc: TexDesc) !void {
        if (resourceRegistry.texPassIdMap.contains(newName) == true) {
            std.debug.print("ERROR: Texture Definition ({s}) already Exists\n", .{newName});
            return error.TextureNameAlreadyExists;
        }
        resourceRegistry.texDefinitions.upsert(texPassId.val(), newTexDesc);
        resourceRegistry.texNames.upsert(texPassId.val(), try .string(newName));

        const persistentName = resourceRegistry.texNames.getConstPtrByKey(texPassId.val()).get();
        resourceRegistry.texPassIdMap.putAssumeCapacity(persistentName, texPassId);
    }

    pub fn removeTextureDefinitionByString(resourceRegistry: *ResourceRegistryData, name: []const u8) void {
        if (resourceRegistry.texPassIdMap.get(name)) |texPassId| {
            resourceRegistry.texPassIdMap.remove(name);
            resourceRegistry.texDefinitions.remove(texPassId.val());
            resourceRegistry.texNames.remove(texPassId.val());
        }
    }

    pub fn addBufferDefinition(resourceRegistry: *ResourceRegistryData, bufPassId: BufPassId, newName: []const u8, newBufDesc: BufDesc) !void {
        if (resourceRegistry.bufPassIdMap.contains(newName) == true) {
            std.debug.print("ERROR: Buffer Definition ({s}) already Exists\n", .{newName});
            return error.BufferNameAlreadyExists;
        }
        resourceRegistry.bufDefinitions.upsert(bufPassId.val(), newBufDesc);
        resourceRegistry.bufNames.upsert(bufPassId.val(), try .string(newName));

        const persistentName = resourceRegistry.bufNames.getConstPtrByKey(bufPassId.val()).get();
        resourceRegistry.bufPassIdMap.putAssumeCapacity(persistentName, bufPassId);
    }

    pub fn removeBufferDefinition(resourceRegistry: *ResourceRegistryData, name: []const u8) void {
        if (resourceRegistry.bufPassIdMap.get(name)) |bufPassId| {
            resourceRegistry.bufPassIdMap.remove(name);
            resourceRegistry.bufDefinitions.remove(bufPassId.val());
            resourceRegistry.bufNames.remove(bufPassId.val());
        }
    }
};
