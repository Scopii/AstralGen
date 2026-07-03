const PassDefinition = @import("../../render/types/pass/PassDefinition.zig").PassDefinition;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const RegistryData = @import("RegistryData.zig").RegistryData;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

pub const RegistrySys = struct {
    pub fn init(self: *RegistryData, alloc: std.mem.Allocator) !void {
        self.passIdMap = std.StringHashMap(PassId).init(alloc);
        try self.passIdMap.ensureTotalCapacity(rc.PASS_MAX);

        self.bufPassIdMap = std.StringHashMap(BufPassId).init(alloc);
        try self.bufPassIdMap.ensureTotalCapacity(rc.BUF_MAX);

        self.texPassIdMap = std.StringHashMap(TexPassId).init(alloc);
        try self.texPassIdMap.ensureTotalCapacity(rc.TEX_MAX);
    }

    pub fn deinit(self: *RegistryData) void {
        self.passIdMap.deinit();
        self.bufPassIdMap.deinit();
        self.texPassIdMap.deinit();
    }

    pub fn addPassDefinition(registryData: *RegistryData, passId: PassId, passDef: PassDefinition) !void {
        try passDef.validate();
        const passName = passDef.name.get();

        if (registryData.passIdMap.contains(passName) == true) {
            std.debug.print("ERROR: Pass Definition ({s}) already Exists\n", .{passName});
            return error.PassNameAlreadyExists;
        }
        registryData.passDefinitions.upsert(passId, passDef);
        registryData.passNames.upsert(passId, try .string(passName));

        const persistentName = registryData.passNames.getConstPtrByKey(passId).get();
        registryData.passIdMap.putAssumeCapacity(persistentName, passId);
    }

    pub fn removePassDefinition(registryData: *RegistryData, name: []const u8) void {
        if (registryData.passIdMap.get(name)) |passId| {
            registryData.passIdMap.remove(name);
            registryData.passDefinitions.remove(passId);
            registryData.passNames.remove(passId);
        }
    }

    pub fn addTextureDefinition(registryData: *RegistryData, texPassId: TexPassId, newName: []const u8, newTexDesc: TexDesc) !void {
        if (registryData.texPassIdMap.contains(newName) == true) {
            std.debug.print("ERROR: Texture Definition ({s}) already Exists\n", .{newName});
            return error.TextureNameAlreadyExists;
        }
        registryData.texDefinitions.upsert(texPassId, newTexDesc);
        registryData.texNames.upsert(texPassId, try .string(newName));

        const persistentName = registryData.texNames.getConstPtrByKey(texPassId).get();
        registryData.texPassIdMap.putAssumeCapacity(persistentName, texPassId);
    }

    pub fn removeTextureDefinitionByString(registryData: *RegistryData, name: []const u8) void {
        if (registryData.texPassIdMap.get(name)) |texPassId| {
            registryData.texPassIdMap.remove(name);
            registryData.texDefinitions.remove(texPassId);
            registryData.texNames.remove(texPassId);
        }
    }

    pub fn addBufferDefinition(registryData: *RegistryData, bufPassId: BufPassId, newName: []const u8, newBufDesc: BufDesc) !void {
        if (registryData.bufPassIdMap.contains(newName) == true) {
            std.debug.print("ERROR: Buffer Definition ({s}) already Exists\n", .{newName});
            return error.BufferNameAlreadyExists;
        }
        registryData.bufDefinitions.upsert(bufPassId, newBufDesc);
        registryData.bufNames.upsert(bufPassId, try .string(newName));

        const persistentName = registryData.bufNames.getConstPtrByKey(bufPassId).get();
        registryData.bufPassIdMap.putAssumeCapacity(persistentName, bufPassId);
    }

    pub fn removeBufferDefinition(registryData: *RegistryData, name: []const u8) void {
        if (registryData.bufPassIdMap.get(name)) |bufPassId| {
            registryData.bufPassIdMap.remove(name);
            registryData.bufDefinitions.remove(bufPassId);
            registryData.bufNames.remove(bufPassId);
        }
    }
};
