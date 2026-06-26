const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const KeyPool = @import("../../.structures/KeyPool.zig").KeyPool;
const rc = @import("../../.configs/renderConfig.zig");
const sc = @import("../../.configs/shaderConfig.zig");
const PassId = @import("../components.zig").PassId;
const std = @import("std");

const String = @import("../../globalHelper.zig").String;

const PassDefinition = @import("../../render/types/pass/PassDefinition.zig").PassDefinition;

const pe = @import("../components.zig");
const TexPassId = pe.TexPassId;
const BufPassId = pe.BufPassId;

pub const ResourceRegistryData = struct {
    bufPassIdMap: std.StringHashMap(BufPassId) = undefined,
    texPassIdMap: std.StringHashMap(TexPassId) = undefined,

    bufNames: LinkedMap(String(30, "BUFFER_NAME_EMPTY"), rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    texNames: LinkedMap(String(30, "TEXTURE_NAME_EMPTY"), rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},

    bufDefinitions: LinkedMap(BufDesc, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    texDefinitions: LinkedMap(TexDesc, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},

    passIdMap: std.StringHashMap(PassId) = undefined, // How should do it correctly ??
    passDefinitions: LinkedMap(PassDefinition, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{},
    passNames: LinkedMap(String(30, "PASS_NAME_EMPTY"), rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{},

    pub fn getPassName(self: *const ResourceRegistryData, passId: PassId) ![]const u8 {
        if (self.passNames.isKeyUsed(passId.val()) == true) return self.passNames.getConstPtrByKey(passId.val()).get() else return error.PassIdHasNoName;
    }

    pub fn getPassId(self: *const ResourceRegistryData, passName: []const u8) !PassId {
        return self.passIdMap.get(passName) orelse return error.PassStringHasNoPassId;
    }

    pub fn getPassDefinition(self: *const ResourceRegistryData, passName: []const u8) !*const PassDefinition {
        const passId = self.passIdMap.get(passName) orelse return error.PassStringHasNoPassId;
        return self.passDefinitions.getConstPtrByKey(passId.val());
    }

    pub fn getBufferPassId(self: *const ResourceRegistryData, name: []const u8) !BufPassId {
        return self.bufPassIdMap.get(name) orelse return error.BufStringHasNoBufPassId;
    }

    pub fn getTexturePassId(self: *const ResourceRegistryData, name: []const u8) !TexPassId {
        return self.texPassIdMap.get(name) orelse return error.TexStringHasNoTexPassId;
    }

    pub fn getBufferName(self: *const ResourceRegistryData, bufPassId: BufPassId) ![]const u8 {
        if (self.bufNames.isKeyUsed(bufPassId.val()) == true) return self.bufNames.getConstPtrByKey(bufPassId.val()).get() else return error.BufPassIdHasNoName;
    }

    pub fn getTextureName(self: *const ResourceRegistryData, texPassId: TexPassId) ![]const u8 {
        if (self.texNames.isKeyUsed(texPassId.val()) == true) return self.texNames.getConstPtrByKey(texPassId.val()).get() else return error.TexPassIdHasNoName;
    }

    pub fn getBufferDefinition(self: *const ResourceRegistryData, bufPassId: BufPassId) !BufDesc {
        if (self.bufDefinitions.isKeyUsed(bufPassId.val()) == true) return self.bufDefinitions.getByKey(bufPassId.val()) else return error.BufPassIdHasNoDefinition;
    }

    pub fn getTextureDefinition(self: *const ResourceRegistryData, texPassId: TexPassId) !TexDesc {
        if (self.texDefinitions.isKeyUsed(texPassId.val()) == true) return self.texDefinitions.getByKey(texPassId.val()) else return error.TexPassIdHasNoDefinition;
    }
};
