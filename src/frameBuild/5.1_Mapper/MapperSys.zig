const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const PassLifetime = @import("../../frameBuild/components.zig").PassLifetime;
const ResDesc = @import("../../frameBuild/components.zig").ResDesc;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const ResPassId = @import("../../.configs/idConfig.zig").ResPassId;
const Group = @import("../../frameBuild/components.zig").Group;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const getResTyp = @import("../../frameBuild/components.zig").getResTyp;
const resToBuf = @import("../../frameBuild/components.zig").resToBuf;
const resToTex = @import("../../frameBuild/components.zig").resToTex;

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const AccessData = @import("../1.5_Access/AccessData.zig").AccessData;
const ResourceData = @import("../2_Resource/ResourceData.zig").ResourceData;
const OptimizerData = @import("../4.5_Optimizer/OptimizerData.zig").OptimizerData;
const LifetimeData = @import("../5_Lifetime/LifetimeData.zig").LifetimeData;
const MapperData = @import("MapperData.zig").MapperData;

// Step 5.1

pub const MapperSys = struct {
    pub fn build(
        mapperData: *MapperData,
        accessData: *const AccessData,
        resourceData: *const ResourceData,
        lifetimeData: *const LifetimeData,
        optimizerData: *const OptimizerData,
        registryData: *const RegistryData,
    ) !void {
        mapperData.transientMap.clear();
        mapperData.persistentMap.clear();

        mapperData.prevTransientGroups = mapperData.transientGroups;
        mapperData.prevPersistentGroups = mapperData.persistentGroups;

        mapperData.transientGroups.clear();
        mapperData.persistentGroups.clear();

        mapperData.transientGroupLifetimes.clear();
        mapperData.linkedResources.clear();
        mapperData.resPassIds.clear();

        for (accessData.accesses.constSlice()) |access| {
            const input = access.input;
            if (mapperData.resPassIds.isKeyUsed(input) == false) mapperData.resPassIds.insert(input, input);

            if (access.output) |output| {
                if (mapperData.resPassIds.isKeyUsed(output) == false) mapperData.resPassIds.insert(output, output);
                try mapperData.linkedResources.append(.{ .in = input, .out = output });
            }
        }

        // Mapping

        while (mapperData.resPassIds.getLength() > 0) {
            const seedKey = mapperData.resPassIds.getLast();
            mapperData.resPassIds.removeLast();
            mapperData.sharedResources.upsert(seedKey, seedKey);

            var readIndex: u32 = 0;
            while (readIndex < mapperData.sharedResources.getLength()) {
                const sharedKey = mapperData.sharedResources.getByIndex(readIndex);
                readIndex += 1;

                const linkedLen = mapperData.linkedResources.len;
                for (0..linkedLen) |li| {
                    const cur = linkedLen - li - 1;
                    const link = mapperData.linkedResources.constSlice()[cur];

                    if (link.in == sharedKey or link.out == sharedKey) {
                        if (mapperData.sharedResources.isKeyUsed(link.in) == false) {
                            mapperData.sharedResources.upsert(link.in, link.in);
                            mapperData.resPassIds.remove(link.in);
                        }
                        if (mapperData.sharedResources.isKeyUsed(link.out) == false) {
                            mapperData.sharedResources.upsert(link.out, link.out);
                            mapperData.resPassIds.remove(link.out);
                        }
                        mapperData.linkedResources.swapRemove(@intCast(cur));
                    }
                }
            }

            // Root selection
            var lastRes: ResPassId = undefined;
            var lastDesc: ?ResDesc = null;
            var lastLifetime: ?PassLifetime = null;
            var rootRes: ResPassId = undefined;

            var groupEarliest: u16 = std.math.maxInt(u16);
            var groupLatest: u16 = 0;

            for (mapperData.sharedResources.getConstItems()) |memberKey| {
                var newDesc: ResDesc = switch (getResTyp(memberKey)) {
                    .Buf => .{ .bufDesc = resourceData.bufDescs.getByKey(resToBuf(memberKey)) },
                    .Tex => .{ .texDesc = resourceData.texDescs.getByKey(resToTex(memberKey)) },
                };
                if (lastDesc) |ld| newDesc = try compareResDesc(lastRes, &ld, memberKey, &newDesc, registryData);

                const newLifetime = lifetimeData.passLifetimes.getByKey(memberKey);

                if (newLifetime.earliest < groupEarliest) groupEarliest = newLifetime.earliest;
                if (newLifetime.latest > groupLatest) groupLatest = newLifetime.latest;

                if (lastLifetime) |last| {
                    if (newLifetime.earliest < last.earliest or (newLifetime.earliest == last.earliest and newLifetime.latest < last.latest)) {
                        lastLifetime = newLifetime;
                        rootRes = memberKey;
                    }
                } else {
                    rootRes = memberKey;
                    lastLifetime = newLifetime;
                }

                lastRes = memberKey;
                lastDesc = newDesc;
            }

            const isTransient = lastDesc.?.isTransient();
            if (isTransient) mapperData.transientGroupLifetimes.appendAssumeCapacity(.{ .rootResource = rootRes, .earliestPass = groupEarliest, .latestPass = groupLatest });
            const map = if (isTransient) &mapperData.transientMap else &mapperData.persistentMap;
            const groups = if (isTransient) &mapperData.transientGroups else &mapperData.persistentGroups;

            for (mapperData.sharedResources.getConstItems()) |memberKey| {
                map.upsert(memberKey, rootRes);
            }

            groups.upsert(rootRes, Group{
                .rootPass = optimizerData.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                .desc = lastDesc.?,
                .firstMapIndex = @intCast(map.getLength() - mapperData.sharedResources.getLength()),
                .lastMapIndex = @intCast(map.getLength() - 1),
            });

            mapperData.sharedResources.clear();
        }

        // Sort Group Lifetimes
        mapperData.transientGroupLifetimes.selectionSort(greaterGroup);
        // mergerData.transientGroupLifetimes.defeatingQuicksort(lessThanGroup);

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.1.ResourceMapper: \n", .{});

            std.debug.print("Previous: \n", .{});
            inline for (.{ mapperData.prevPersistentGroups, mapperData.prevTransientGroups }, .{ "Persistent", "Transient" }) |groups, label| {
                for (groups.getConstItems(), 0..) |group, i| {
                    const rootRes = groups.getKeyByIndex(@intCast(i));
                    const rootTyp = getResTyp(rootRes);
                    const rootName = try registryData.getResourceName(rootRes);
                    const rootPass = try registryData.getPassName(group.rootPass);
                    std.debug.print("{s}Group ({s} {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ @tagName(rootTyp), label, i, rootName, rootPass, group.firstMapIndex, group.lastMapIndex });
                }
            }

            std.debug.print("\nCurrent: \n", .{});
            // Persistent Groups
            for (mapperData.persistentGroups.getConstItems(), 0..) |group, i| {
                const rootRes = mapperData.persistentGroups.getKeyByIndex(@intCast(i));
                const rootTyp = getResTyp(rootRes);
                const rootName = try registryData.getResourceName(rootRes);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("{s}Group (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ @tagName(rootTyp), i, rootName, rootPass, group.firstMapIndex, group.lastMapIndex });

                for (group.firstMapIndex..group.lastMapIndex + 1, 0..) |mapIndex, counter| {
                    const memberRes = mapperData.persistentMap.getKeyByIndex(@intCast(mapIndex));
                    const memberName = try registryData.getResourceName(memberRes);
                    std.debug.print("     -> {}. {s}\n", .{ counter, memberName });
                }
            }
            // Transient Groups
            for (mapperData.transientGroups.getConstItems(), 0..) |group, i| {
                const rootRes = mapperData.transientGroups.getKeyByIndex(@intCast(i));
                const rootTyp = getResTyp(rootRes);
                const rootName = try registryData.getResourceName(rootRes);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("{s}Group (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ @tagName(rootTyp), i, rootName, rootPass, group.firstMapIndex, group.lastMapIndex });

                for (group.firstMapIndex..group.lastMapIndex + 1, 0..) |mapIndex, counter| {
                    const memberRes = mapperData.transientMap.getKeyByIndex(@intCast(mapIndex));
                    const memberName = try registryData.getResourceName(memberRes);
                    std.debug.print("     -> {}. {s}\n", .{ counter, memberName });
                }
            }
            std.debug.print("Transient Group Lifetimes: \n", .{});
            for (mapperData.transientGroupLifetimes.constSlice(), 0..) |groupLifetime, i| {
                const resTyp = getResTyp(groupLifetime.rootResource);
                const resName = try registryData.getResourceName(groupLifetime.rootResource);
                std.debug.print("- {}. Transient {s} Group (Root {s}) (Pass {} -> Pass {})\n", .{ i, @tagName(resTyp), resName, groupLifetime.earliestPass, groupLifetime.latestPass });
            }
            std.debug.print("\n", .{});
            std.debug.print("\n", .{});
        }
    }
};

fn compareResDesc(key1: ResPassId, desc1: *const ResDesc, key2: ResPassId, desc2: *const ResDesc, registryData: *const RegistryData) !ResDesc {
    if (std.meta.activeTag(desc1.*) != std.meta.activeTag(desc2.*)) return error.ResourceKindsMixedInGroup; // can't happen via valid links; catches bugs
    return switch (desc1.*) {
        .bufDesc => |d1| .{ .bufDesc = try compareBufDesc(resToBuf(key1), &d1, resToBuf(key2), &desc2.bufDesc, registryData) },
        .texDesc => |d1| .{ .texDesc = try compareTexDesc(resToTex(key1), &d1, resToTex(key2), &desc2.texDesc, registryData) },
    };
}

fn compareBufDesc(bufId1: BufPassId, bufDesc1: *const BufDesc, bufId2: BufPassId, bufDesc2: *const BufDesc, registryData: *const RegistryData) !BufDesc {
    const equal = if (std.meta.eql(bufDesc1.*, bufDesc2.*)) true else false;

    if (equal == false) {
        const bufName1 = try registryData.getBufferName(bufId1);
        const bufName2 = try registryData.getBufferName(bufId2);
        std.debug.print("ERROR: ResourceMapperSys: Buffer Descriptions dont match \n({s}:{})\n({s}:{})\n", .{ bufName1, bufDesc1, bufName2, bufDesc2 });
        return error.BufferDescriptionsDontMatch;
    }

    return bufDesc1.*;
}

fn compareTexDesc(texId1: TexPassId, texDesc1: *const TexDesc, texId2: TexPassId, texDesc2: *const TexDesc, registryData: *const RegistryData) !TexDesc {
    // const equal = if (std.meta.eql(texDesc1.*, texDesc2.*)) true else false;

    const equal = if (texDesc1.share == texDesc2.share and
        texDesc1.mem == texDesc2.mem and
        texDesc1.typ == texDesc2.typ and
        texDesc1.texUse == texDesc2.texUse and
        texDesc1.descriptors == texDesc2.descriptors and
        // texDesc1.width == texDesc2.width and
        // texDesc1.height == texDesc2.height and
        texDesc1.depth == texDesc2.depth and
        texDesc1.update == texDesc2.update and
        texDesc1.resize == texDesc2.resize and
        texDesc1.fitPass == texDesc2.fitPass)
        true
    else
        false;

    const maxWidth = @max(texDesc1.width, texDesc2.width);
    const maxHeight = @max(texDesc1.height, texDesc2.height);

    if (equal == false) {
        const texName1 = try registryData.getTextureName(texId1);
        const texName2 = try registryData.getTextureName(texId2);
        std.debug.print("ERROR: ResourceMapperSys: Texture Descriptions dont match \n({s}:{})\n({s}:{})\n", .{ texName1, texDesc1, texName2, texDesc2 });
        return error.TextureDescriptionsDontMatch;
    }

    return TexDesc{
        .share = texDesc1.share,
        .mem = texDesc1.mem,
        .typ = texDesc1.typ,
        .texUse = texDesc1.texUse,
        .descriptors = texDesc1.descriptors,
        .depth = texDesc1.depth,
        .width = maxWidth,
        .height = maxHeight,
        .update = texDesc1.update,
        .resize = texDesc1.resize,
        .fitPass = texDesc1.fitPass,
    };
}

fn lessThanGroup(group1: anytype, group2: anytype) bool {
    if (group1.earliestPass != group2.earliestPass) return group1.earliestPass < group2.earliestPass;
    return group1.latestPass < group2.latestPass;
}

fn greaterGroup(group1: anytype, group2: anytype) bool {
    if (group1.earliestPass != group2.earliestPass) return group1.earliestPass > group2.earliestPass;
    return group1.latestPass > group2.latestPass;
}
