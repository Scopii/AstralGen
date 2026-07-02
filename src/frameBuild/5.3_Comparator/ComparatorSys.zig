const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TexGroupChange = @import("../../frameBuild/components.zig").TexGroupChange;
const BufGroupChange = @import("../../frameBuild/components.zig").BufGroupChange;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const MapperData = @import("../5.1_Mapper/MapperData.zig").MapperData;
const ComparatorData = @import("ComparatorData.zig").ComparatorData;

// Step 6

pub const ComparatorSys = struct {
    pub fn buildChanges(comparatorData: *ComparatorData, mapperData: *const MapperData, registryData: *const RegistryData) !void {
        comparatorData.persistentBufChanges.clear();
        comparatorData.persistentTexChanges.clear();

        // Buffer Changes
        for (mapperData.bufGroupsPersistent.getConstItems(), 0..) |newGroupInf, i| {
            const groupRootKey: u16 = mapperData.bufGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootId: BufPassId = .id(groupRootKey);

            const isGroupInLast = mapperData.lastBufGroupsPersistent.isKeyUsed(groupRootKey);

            if (isGroupInLast == true) {
                const lastGroupInf = mapperData.lastBufGroupsPersistent.getByKey(groupRootKey);

                const newDesc = !bufDescEqual(&lastGroupInf.bufDesc, &newGroupInf.bufDesc);
                const newPass = if (lastGroupInf.rootPass.val() == newGroupInf.rootPass.val()) false else true;

                if (newDesc == true and newPass == true) comparatorData.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootId, .change = .newPassAndDesc });
                if (newDesc == true and newPass == false) comparatorData.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootId, .change = .newDesc });
                if (newDesc == false and newPass == true) comparatorData.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootId, .change = .newPass });
                if (newDesc == false and newPass == false) comparatorData.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootId, .change = .unchanged });
            } else {
                comparatorData.persistentBufChanges.appendAssumeCapacity(BufGroupChange{ .rootBuf = groupRootId, .change = .created });
            }
        }

        for (0..mapperData.lastBufGroupsPersistent.getLength()) |i| {
            const groupRootKey: u16 = mapperData.lastBufGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootId: BufPassId = .id(groupRootKey);

            const isGroupInNew = mapperData.bufGroupsPersistent.isKeyUsed(groupRootKey);
            if (isGroupInNew == false) comparatorData.persistentBufChanges.appendAssumeCapacity(BufGroupChange{ .rootBuf = groupRootId, .change = .deleted });
        }

        // Texture Changes
        for (mapperData.texGroupsPersistent.getConstItems(), 0..) |newGroupInf, i| {
            const groupRootKey: u16 = mapperData.texGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootId: TexPassId = .id(groupRootKey);

            const isGroupInLast = mapperData.lastTexGroupsPersistent.isKeyUsed(groupRootKey);

            if (isGroupInLast == true) {
                const lastGroupInf = mapperData.lastTexGroupsPersistent.getByKey(groupRootKey);

                const newDesc = !texDescEqual(&lastGroupInf.texDesc, &newGroupInf.texDesc);
                const newPass = if (lastGroupInf.rootPass.val() == newGroupInf.rootPass.val()) false else true;

                if (newDesc == true and newPass == true) comparatorData.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootId, .change = .newPassAndDesc });
                if (newDesc == true and newPass == false) comparatorData.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootId, .change = .newDesc });
                if (newDesc == false and newPass == true) comparatorData.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootId, .change = .newPass });
                if (newDesc == false and newPass == false) comparatorData.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootId, .change = .unchanged });
            } else {
                comparatorData.persistentTexChanges.appendAssumeCapacity(TexGroupChange{ .rootTex = groupRootId, .change = .created });
            }
        }

        for (0..mapperData.lastTexGroupsPersistent.getLength()) |i| {
            const groupRootKey: u16 = mapperData.lastTexGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootId: TexPassId = .id(groupRootKey);

            const isGroupInNew = mapperData.texGroupsPersistent.isKeyUsed(groupRootKey);
            if (isGroupInNew == false) comparatorData.persistentTexChanges.appendAssumeCapacity(TexGroupChange{ .rootTex = groupRootId, .change = .deleted });
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.3.MappingComparator: \n", .{});
            for (comparatorData.persistentBufChanges.constSlice()) |bufGroupChange| {
                const rootBuf = try registryData.getBufferName(bufGroupChange.rootBuf);
                std.debug.print("- Persistent BufGroup {s}: {s}\n", .{ rootBuf, @tagName(bufGroupChange.change) });
            }
            for (comparatorData.persistentTexChanges.constSlice()) |texGroupChange| {
                const rootTex = try registryData.getTextureName(texGroupChange.rootTex);
                std.debug.print("- Persistent TexGroup {s}: {s}\n", .{ rootTex, @tagName(texGroupChange.change) });
            }
            std.debug.print("\n", .{});
        }
    }
};

fn bufDescEqual(bufDesc1: *const BufDesc, bufDesc2: *const BufDesc) bool {
    return std.meta.eql(bufDesc1.*, bufDesc2.*);
}

fn texDescEqual(texDesc1: *const TexDesc, texDesc2: *const TexDesc) bool {
    return std.meta.eql(texDesc1.*, texDesc2.*);
}
