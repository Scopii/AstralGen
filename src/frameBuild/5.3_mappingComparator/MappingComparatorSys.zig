const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TexGroupChange = @import("../../frameBuild/components.zig").TexGroupChange;
const BufGroupChange = @import("../../frameBuild/components.zig").BufGroupChange;
const TexPassId = @import("../components.zig").TexPassId;
const BufPassId = @import("../components.zig").BufPassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const ResourceMapperData = @import("../5.1_resourceMapper/ResourceMapperData.zig").ResourceMapperData;
const MappingComparatorData = @import("MappingComparatorData.zig").MappingComparatorData;

// Step 6

pub const MappingComparatorSys = struct {
    pub fn buildChanges(mappingComparator: *MappingComparatorData, resourceMapper: *const ResourceMapperData, resourceRegistry: *const ResourceRegistryData) !void {
        mappingComparator.persistentBufChanges.clear();
        mappingComparator.persistentTexChanges.clear();

        // Buffer Changes
        for (resourceMapper.bufGroupsPersistent.getConstItems(), 0..) |newGroupInf, i| {
            const groupRootKey: u16 = resourceMapper.bufGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootId: BufPassId = .id(groupRootKey);

            const isGroupInLast = resourceMapper.lastBufGroupsPersistent.isKeyUsed(groupRootKey);

            if (isGroupInLast == true) {
                const lastGroupInf = resourceMapper.lastBufGroupsPersistent.getByKey(groupRootKey);

                const newDesc = !bufDescEqual(&lastGroupInf.bufDesc, &newGroupInf.bufDesc);
                const newPass = if (lastGroupInf.rootPass.val() == newGroupInf.rootPass.val()) false else true;

                if (newDesc == true and newPass == true) mappingComparator.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootId, .change = .newDesc });
                if (newDesc == true and newPass == false) mappingComparator.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootId, .change = .newPass });
                if (newDesc == false and newPass == true) mappingComparator.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootId, .change = .newPassAndDesc });
                if (newDesc == false and newPass == false) mappingComparator.persistentBufChanges.appendAssumeCapacity(.{ .rootBuf = groupRootId, .change = .unchanged });
            } else {
                mappingComparator.persistentBufChanges.appendAssumeCapacity(BufGroupChange{ .rootBuf = groupRootId, .change = .created });
            }
        }

        for (0..resourceMapper.lastBufGroupsPersistent.getLength()) |i| {
            const groupRootKey: u16 = resourceMapper.bufGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootId: BufPassId = .id(groupRootKey);

            const isGroupInNew = resourceMapper.bufGroupsPersistent.isKeyUsed(groupRootKey);
            if (isGroupInNew == false) mappingComparator.persistentBufChanges.appendAssumeCapacity(BufGroupChange{ .rootBuf = groupRootId, .change = .deleted });
        }

        // Texture Changes
        for (resourceMapper.texGroupsPersistent.getConstItems(), 0..) |newGroupInf, i| {
            const groupRootKey: u16 = resourceMapper.texGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootId: TexPassId = .id(groupRootKey);

            const isGroupInLast = resourceMapper.lastTexGroupsPersistent.isKeyUsed(groupRootKey);

            if (isGroupInLast == true) {
                const lastGroupInf = resourceMapper.lastTexGroupsPersistent.getByKey(groupRootKey);

                const newDesc = !texDescEqual(&lastGroupInf.texDesc, &newGroupInf.texDesc);
                const newPass = if (lastGroupInf.rootPass.val() == newGroupInf.rootPass.val()) false else true;

                if (newDesc == true and newPass == true) mappingComparator.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootId, .change = .newDesc });
                if (newDesc == true and newPass == false) mappingComparator.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootId, .change = .newPass });
                if (newDesc == false and newPass == true) mappingComparator.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootId, .change = .newPassAndDesc });
                if (newDesc == false and newPass == false) mappingComparator.persistentTexChanges.appendAssumeCapacity(.{ .rootTex = groupRootId, .change = .unchanged });
            } else {
                mappingComparator.persistentTexChanges.appendAssumeCapacity(TexGroupChange{ .rootTex = groupRootId, .change = .created });
            }
        }

        for (0..resourceMapper.lastTexGroupsPersistent.getLength()) |i| {
            const groupRootKey: u16 = resourceMapper.texGroupsPersistent.getKeyByIndex(@intCast(i));
            const groupRootId: TexPassId = .id(groupRootKey);

            const isGroupInNew = resourceMapper.texGroupsPersistent.isKeyUsed(groupRootKey);
            if (isGroupInNew == false) mappingComparator.persistentTexChanges.appendAssumeCapacity(TexGroupChange{ .rootTex = groupRootId, .change = .deleted });
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.3.MappingComparator: \n", .{});
            for (mappingComparator.persistentBufChanges.constSlice()) |bufGroupChange| {
                const rootBufName = try resourceRegistry.getBufferName(bufGroupChange.rootBuf);
                std.debug.print("- Persistent BufGroup {s}: {s}\n", .{ rootBufName, @tagName(bufGroupChange.change) });
            }
            for (mappingComparator.persistentTexChanges.constSlice()) |texGroupChange| {
                const rootTexName = try resourceRegistry.getTextureName(texGroupChange.rootTex);
                std.debug.print("- Persistent TexGroup {s}: {s}\n", .{ rootTexName, @tagName(texGroupChange.change) });
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
