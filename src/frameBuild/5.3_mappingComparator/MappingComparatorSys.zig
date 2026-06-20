const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TexGroupChange = @import("../../frameBuild/components.zig").TexGroupChange;
const BufGroupChange = @import("../../frameBuild/components.zig").BufGroupChange;
const rc = @import("../../.configs/renderConfig.zig");
const pe = @import("../enums.zig");
const std = @import("std");

const ResourceMapperData = @import("../5.1_resourceMapper/ResourceMapperData.zig").ResourceMapperData;
const MappingComparatorData = @import("MappingComparatorData.zig").MappingComparatorData;

const TextureEnum = pe.TextureEnum;
const BufferEnum = pe.BufferEnum;

// Step 6

pub const MappingComparatorSys = struct {
    pub fn buildChanges(mappingComparator: *MappingComparatorData, resourceMapper: *const ResourceMapperData) void {
        mappingComparator.persistentBufChanges.clear();
        mappingComparator.persistentTexChanges.clear();

        // Buffer Changes
        for (resourceMapper.bufGroupsPersistent.getConstItems(), 0..) |newGroupInf, i| {
            const groupRootKey: u16 = resourceMapper.bufGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootEnum: BufferEnum = @enumFromInt(groupRootKey);

            const isGroupInLast = resourceMapper.lastBufGroupsPersistent.isKeyUsed(groupRootKey);

            if (isGroupInLast == true) {
                const lastGroupInf = resourceMapper.lastBufGroupsPersistent.getByKey(groupRootKey);

                const newDesc = !bufDescEqual(&lastGroupInf.bufDesc, &newGroupInf.bufDesc);
                const newPass = if (lastGroupInf.rootPass.val == newGroupInf.rootPass.val) false else true;

                if (newDesc == true and newPass == true) mappingComparator.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootEnum, .change = .newDesc });
                if (newDesc == true and newPass == false) mappingComparator.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootEnum, .change = .newPass });
                if (newDesc == false and newPass == true) mappingComparator.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootEnum, .change = .newPassAndDesc });
                if (newDesc == false and newPass == false) mappingComparator.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootEnum, .change = .unchanged });
            } else {
                mappingComparator.persistentBufChanges.appendAssumeCapacity(BufGroupChange{ .rootBuf = groupRootEnum, .change = .created });
            }
        }

        for (0..resourceMapper.lastBufGroupsPersistent.getLength()) |i| {
            const groupRootKey: u16 = resourceMapper.bufGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootEnum: BufferEnum = @enumFromInt(groupRootKey);

            const isGroupInNew = resourceMapper.bufGroupsPersistent.isKeyUsed(groupRootKey);
            if (isGroupInNew == false) mappingComparator.persistentBufChanges.appendAssumeCapacity(BufGroupChange{ .rootBuf = groupRootEnum, .change = .deleted });
        }

        // Texture Changes
        for (resourceMapper.texGroupsPersistent.getConstItems(), 0..) |newGroupInf, i| {
            const groupRootKey: u16 = resourceMapper.texGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootEnum: TextureEnum = @enumFromInt(groupRootKey);

            const isGroupInLast = resourceMapper.lastTexGroupsPersistent.isKeyUsed(groupRootKey);

            if (isGroupInLast == true) {
                const lastGroupInf = resourceMapper.lastTexGroupsPersistent.getByKey(groupRootKey);

                const newDesc = !texDescEqual(&lastGroupInf.texDesc, &newGroupInf.texDesc);
                const newPass = if (lastGroupInf.rootPass.val == newGroupInf.rootPass.val) false else true;

                if (newDesc == true and newPass == true) mappingComparator.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootEnum, .change = .newDesc });
                if (newDesc == true and newPass == false) mappingComparator.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootEnum, .change = .newPass });
                if (newDesc == false and newPass == true) mappingComparator.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootEnum, .change = .newPassAndDesc });
                if (newDesc == false and newPass == false) mappingComparator.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootEnum, .change = .unchanged });
            } else {
                mappingComparator.persistentTexChanges.appendAssumeCapacity(TexGroupChange{ .rootTex = groupRootEnum, .change = .created });
            }
        }

        for (0..resourceMapper.lastTexGroupsPersistent.getLength()) |i| {
            const groupRootKey: u16 = resourceMapper.texGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootEnum: TextureEnum = @enumFromInt(groupRootKey);

            const isGroupInNew = resourceMapper.texGroupsPersistent.isKeyUsed(groupRootKey);
            if (isGroupInNew == false) mappingComparator.persistentTexChanges.appendAssumeCapacity(TexGroupChange{ .rootTex = groupRootEnum, .change = .deleted });
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.3.MappingComparator: \n", .{});
            for (mappingComparator.persistentBufChanges.constSlice()) |bufGroupChange| {
                std.debug.print("- Persistent BufGroup {s}: {s}\n", .{ @tagName(bufGroupChange.rootBuf), @tagName(bufGroupChange.change) });
            }
            for (mappingComparator.persistentTexChanges.constSlice()) |texGroupChange| {
                std.debug.print("- Persistent TexGroup {s}: {s}\n", .{ @tagName(texGroupChange.rootTex), @tagName(texGroupChange.change) });
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
