const PassDefinition = @import("../render/types/pass/PassDefinition.zig").PassDefinition;
const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const Pass = @import("../render/types/pass/PassDefinition.zig").Pass;
const KeyPool = @import("../.structures/KeyPool.zig").KeyPool;
const PassId = @import("../.configs/idConfig.zig").PassId;
const String = @import("../globalHelper.zig").String;
const rc = @import("../.configs/renderConfig.zig");
const pe = @import("../.configs/idConfig.zig");
const std = @import("std");
const TexPassId = pe.TexPassId;
const BufPassId = pe.BufPassId;

pub const RenderRegistryData = struct {
    bufPool: KeyPool(u16, rc.BUF_MAX) = .{},
    texPool: KeyPool(u16, rc.TEX_MAX) = .{},
    passPool: KeyPool(u16, rc.PASS_MAX) = .{},

    bufPassIdMap: std.StringHashMap(BufPassId) = undefined,
    texPassIdMap: std.StringHashMap(TexPassId) = undefined,

    bufNames: LinkedIdMap(String(30, "BUFFER_NAME_EMPTY"), rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texNames: LinkedIdMap(String(30, "TEXTURE_NAME_EMPTY"), rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    bufDefinitions: LinkedIdMap(BufDesc, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texDefinitions: LinkedIdMap(TexDesc, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    passIdMap: std.StringHashMap(PassId) = undefined, // How should do it correctly ??
    passes: LinkedIdMap(Pass, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    passNames: LinkedIdMap(String(30, "PASS_NAME_EMPTY"), rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},

    pub fn getPassName(self: *const RenderRegistryData, passId: PassId) ![]const u8 {
        if (self.passNames.isKeyUsed(passId) == true) return self.passNames.getConstPtrByKey(passId).get() else return error.PassIdHasNoName;
    }

    pub fn getPassId(self: *const RenderRegistryData, passName: []const u8) !PassId {
        return self.passIdMap.get(passName) orelse {
            std.debug.print("ERROR in RenderRegistry: {s} has no PassId\n", .{passName});
            return error.PassStringHasNoPassId;
        };
    }

    pub fn getPass(self: *const RenderRegistryData, passName: []const u8) !*const Pass {
        const passId = self.passIdMap.get(passName) orelse return error.PassStringHasNoPassId;
        return self.passes.getConstPtrByKey(passId);
    }

    pub fn getPassById(self: *const RenderRegistryData, passId: PassId) !*const Pass {
        if (self.passes.isKeyUsed(passId) == true) return self.passes.getConstPtrByKey(passId) else return error.PassIdHasNoDefinition;
    }

    pub fn getBufferPassId(self: *const RenderRegistryData, name: []const u8) !BufPassId {
        return self.bufPassIdMap.get(name) orelse {
            std.debug.print("ERROR in RenderRegistry: {s} has no BufPassId\n", .{name});
            return error.BufStringHasNoBufPassId;
        };
    }

    pub fn getTexturePassId(self: *const RenderRegistryData, name: []const u8) !TexPassId {
        return self.texPassIdMap.get(name) orelse {
            std.debug.print("ERROR in RenderRegistry: {s} has no TexPassId\n", .{name});
            return error.TexStringHasNoTexPassId;
        };
    }

    pub fn getBufferName(self: *const RenderRegistryData, bufPassId: BufPassId) ![]const u8 {
        if (self.bufNames.isKeyUsed(bufPassId) == true) return self.bufNames.getConstPtrByKey(bufPassId).get() else return error.BufPassIdHasNoName;
    }

    pub fn getTextureName(self: *const RenderRegistryData, texPassId: TexPassId) ![]const u8 {
        if (self.texNames.isKeyUsed(texPassId) == true) return self.texNames.getConstPtrByKey(texPassId).get() else return error.TexPassIdHasNoName;
    }

    pub fn getBufferDefinition(self: *const RenderRegistryData, bufPassId: BufPassId) !BufDesc {
        if (self.bufDefinitions.isKeyUsed(bufPassId) == true) return self.bufDefinitions.getByKey(bufPassId) else return error.BufPassIdHasNoDefinition;
    }

    pub fn getTextureDefinition(self: *const RenderRegistryData, texPassId: TexPassId) !TexDesc {
        if (self.texDefinitions.isKeyUsed(texPassId) == true) return self.texDefinitions.getByKey(texPassId) else return error.TexPassIdHasNoDefinition;
    }
};
