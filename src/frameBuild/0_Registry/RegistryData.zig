const PassDefinition = @import("../../render/types/pass/PassDefinition.zig").PassDefinition;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const KeyPool = @import("../../.structures/KeyPool.zig").KeyPool;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const String = @import("../../globalHelper.zig").String;
const rc = @import("../../.configs/renderConfig.zig");
const pe = @import("../../.configs/idConfig.zig");
const std = @import("std");
const TexPassId = pe.TexPassId;
const BufPassId = pe.BufPassId;

pub const RegistryData = struct {
    bufPassIdMap: std.StringHashMap(BufPassId) = undefined,
    texPassIdMap: std.StringHashMap(TexPassId) = undefined,

    bufNames: LinkedIdMap(String(30, "BUFFER_NAME_EMPTY"), rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texNames: LinkedIdMap(String(30, "TEXTURE_NAME_EMPTY"), rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    bufDefinitions: LinkedIdMap(BufDesc, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texDefinitions: LinkedIdMap(TexDesc, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    passIdMap: std.StringHashMap(PassId) = undefined, // How should do it correctly ??
    passDefinitions: LinkedIdMap(PassDefinition, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    passNames: LinkedIdMap(String(30, "PASS_NAME_EMPTY"), rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},

    pub fn getPassName(self: *const RegistryData, passId: PassId) ![]const u8 {
        if (self.passNames.isKeyUsed(passId) == true) return self.passNames.getConstPtrByKey(passId).get() else return error.PassIdHasNoName;
    }

    pub fn getPassId(self: *const RegistryData, passName: []const u8) !PassId {
        return self.passIdMap.get(passName) orelse return error.PassStringHasNoPassId;
    }

    pub fn getPassDefinition(self: *const RegistryData, passName: []const u8) !*const PassDefinition {
        const passId = self.passIdMap.get(passName) orelse return error.PassStringHasNoPassId;
        return self.passDefinitions.getConstPtrByKey(passId);
    }

    pub fn getPassDefinitionById(self: *const RegistryData, passId: PassId) !*const PassDefinition {
        if (self.passDefinitions.isKeyUsed(passId) == true) return self.passDefinitions.getConstPtrByKey(passId) else return error.PassIdHasNoDefinition;
    }

    pub fn getBufferPassId(self: *const RegistryData, name: []const u8) !BufPassId {
        return self.bufPassIdMap.get(name) orelse return error.BufStringHasNoBufPassId;
    }

    pub fn getTexturePassId(self: *const RegistryData, name: []const u8) !TexPassId {
        return self.texPassIdMap.get(name) orelse return error.TexStringHasNoTexPassId;
    }

    pub fn getBufferName(self: *const RegistryData, bufPassId: BufPassId) ![]const u8 {
        if (self.bufNames.isKeyUsed(bufPassId) == true) return self.bufNames.getConstPtrByKey(bufPassId).get() else return error.BufPassIdHasNoName;
    }

    pub fn getTextureName(self: *const RegistryData, texPassId: TexPassId) ![]const u8 {
        if (self.texNames.isKeyUsed(texPassId) == true) return self.texNames.getConstPtrByKey(texPassId).get() else return error.TexPassIdHasNoName;
    }

    pub fn getBufferDefinition(self: *const RegistryData, bufPassId: BufPassId) !BufDesc {
        if (self.bufDefinitions.isKeyUsed(bufPassId) == true) return self.bufDefinitions.getByKey(bufPassId) else return error.BufPassIdHasNoDefinition;
    }

    pub fn getTextureDefinition(self: *const RegistryData, texPassId: TexPassId) !TexDesc {
        if (self.texDefinitions.isKeyUsed(texPassId) == true) return self.texDefinitions.getByKey(texPassId) else return error.TexPassIdHasNoDefinition;
    }
};
