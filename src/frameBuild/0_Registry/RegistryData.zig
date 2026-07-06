const PassDefinition = @import("../../render/types/pass/PassDefinition.zig").PassDefinition;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const ResPassId = @import("../../.configs/idConfig.zig").ResPassId;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const String = @import("../../globalHelper.zig").String;
const rc = @import("../../.configs/renderConfig.zig");
const pe = @import("../../.configs/idConfig.zig");
const std = @import("std");
const TexPassId = pe.TexPassId;
const BufPassId = pe.BufPassId;

const getResTyp = @import("../components.zig").getResTyp;
const resToBuf = @import("../components.zig").resToBuf;
const resToTex = @import("../components.zig").resToTex;

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

    pub fn getResourceName(self: *const RegistryData, resPassId: ResPassId) ![]const u8 {
        return switch (getResTyp(resPassId)) {
            .Buf => try getBufferName(self, resToBuf(resPassId)),
            .Tex => try getTextureName(self, resToTex(resPassId)),
        };
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
