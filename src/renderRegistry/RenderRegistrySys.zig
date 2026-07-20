const PassDefinition = @import("../render/types/pass/PassDefinition.zig").PassDefinition;
const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const RenderRegistryData = @import("RenderRegistryData.zig").RenderRegistryData;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const PassId = @import("../.configs/idConfig.zig").PassId;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

const depthViewPass = @import("../.assets/passes/depthView/DepthView.zig").depthViewPass;
const compRayMarchPass = @import("../.assets/passes/compTest/CompRayMarch.zig").compRayMarchPass;
const editorGridGridDebugPass = @import("../.assets/passes/editorGrid/EditorGrid.zig").editorGridGridDebugPass;
const editorGridPlaneDebugPass = @import("../.assets/passes/editorGrid/EditorGrid.zig").editorGridPlaneDebugPass;
const frustumViewPass = @import("../.assets/passes/quant/FrustumView.zig").frustumViewPass;
const quantGridPass = @import("../.assets/passes/quant/Quant.zig").quantGridPass;
const quantGridDebugPass = @import("../.assets/passes/quant/Quant.zig").quantGridDebugPass;
const quantPlanePass = @import("../.assets/passes/quant/Quant.zig").quantPlanePass;
const quantPlaneDebugPass = @import("../.assets/passes/quant/Quant.zig").quantPlaneDebugPass;
const quantCompPass = @import("../.assets/passes/quant/QuantComp.zig").quantCompPass;

pub const RenderRegistrySys = struct {
    pub fn init(self: *RenderRegistryData, alloc: std.mem.Allocator) !void {
        self.passIdMap = std.StringHashMap(PassId).init(alloc);
        try self.passIdMap.ensureTotalCapacity(rc.PASS_MAX);

        self.bufPassIdMap = std.StringHashMap(BufPassId).init(alloc);
        try self.bufPassIdMap.ensureTotalCapacity(rc.BUF_MAX);

        self.texPassIdMap = std.StringHashMap(TexPassId).init(alloc);
        try self.texPassIdMap.ensureTotalCapacity(rc.TEX_MAX);
    }

    pub fn deinit(self: *RenderRegistryData) void {
        self.passIdMap.deinit();
        self.bufPassIdMap.deinit();
        self.texPassIdMap.deinit();
    }

    pub fn addPassDefinition(registry: *RenderRegistryData, passId: PassId, passDef: PassDefinition) !void {
        try passDef.validate();
        const passName = passDef.name.get();

        if (registry.passIdMap.contains(passName) == true) {
            std.debug.print("ERROR: Pass Definition ({s}) already Exists\n", .{passName});
            return error.PassNameAlreadyExists;
        }
        registry.passDefinitions.upsert(passId, passDef);
        registry.passNames.upsert(passId, try .string(passName));

        const persistentName = registry.passNames.getConstPtrByKey(passId).get();
        registry.passIdMap.putAssumeCapacity(persistentName, passId);
    }

    pub fn removePassDefinition(registry: *RenderRegistryData, name: []const u8) void {
        if (registry.passIdMap.get(name)) |passId| {
            registry.passIdMap.remove(name);
            registry.passDefinitions.remove(passId);
            registry.passNames.remove(passId);
        }
    }

    pub fn addTextureDefinition(registry: *RenderRegistryData, texPassId: TexPassId, newName: []const u8, newTexDesc: TexDesc) !void {
        if (registry.texPassIdMap.contains(newName) == true) {
            std.debug.print("ERROR: Texture Definition ({s}) already Exists\n", .{newName});
            return error.TextureNameAlreadyExists;
        }
        registry.texDefinitions.upsert(texPassId, newTexDesc);
        registry.texNames.upsert(texPassId, try .string(newName));

        const persistentName = registry.texNames.getConstPtrByKey(texPassId).get();
        registry.texPassIdMap.putAssumeCapacity(persistentName, texPassId);
    }

    pub fn removeTextureDefinitionByString(registry: *RenderRegistryData, name: []const u8) void {
        if (registry.texPassIdMap.get(name)) |texPassId| {
            registry.texPassIdMap.remove(name);
            registry.texDefinitions.remove(texPassId);
            registry.texNames.remove(texPassId);
        }
    }

    pub fn addBufferDefinition(registry: *RenderRegistryData, bufPassId: BufPassId, newName: []const u8, newBufDesc: BufDesc) !void {
        if (registry.bufPassIdMap.contains(newName) == true) {
            std.debug.print("ERROR: Buffer Definition ({s}) already Exists\n", .{newName});
            return error.BufferNameAlreadyExists;
        }
        registry.bufDefinitions.upsert(bufPassId, newBufDesc);
        registry.bufNames.upsert(bufPassId, try .string(newName));

        const persistentName = registry.bufNames.getConstPtrByKey(bufPassId).get();
        registry.bufPassIdMap.putAssumeCapacity(persistentName, bufPassId);
    }

    pub fn removeBufferDefinition(registry: *RenderRegistryData, name: []const u8) void {
        if (registry.bufPassIdMap.get(name)) |bufPassId| {
            registry.bufPassIdMap.remove(name);
            registry.bufDefinitions.remove(bufPassId);
            registry.bufNames.remove(bufPassId);
        }
    }

    pub fn setupDefinitions(self: *RenderRegistryData) !void {
        try RenderRegistrySys.addPassDefinition(self, .id(0), depthViewPass);
        try RenderRegistrySys.addPassDefinition(self, .id(1), compRayMarchPass);
        try RenderRegistrySys.addPassDefinition(self, .id(2), editorGridGridDebugPass);
        try RenderRegistrySys.addPassDefinition(self, .id(3), editorGridPlaneDebugPass);
        try RenderRegistrySys.addPassDefinition(self, .id(4), frustumViewPass);
        try RenderRegistrySys.addPassDefinition(self, .id(5), quantGridPass);
        try RenderRegistrySys.addPassDefinition(self, .id(6), quantGridDebugPass);
        try RenderRegistrySys.addPassDefinition(self, .id(7), quantPlanePass);
        try RenderRegistrySys.addPassDefinition(self, .id(8), quantPlaneDebugPass);
        try RenderRegistrySys.addPassDefinition(self, .id(9), quantCompPass);

        // Buffers
        try RenderRegistrySys.addBufferDefinition(self, rc.QuantIndirectInputSB, "QuantIndirectInputSB", rc.indirectSBDesc);
        try RenderRegistrySys.addBufferDefinition(self, rc.QuantIndirectOutputSB, "QuantIndirectOutputSB", rc.indirectSBDesc);
        try RenderRegistrySys.addBufferDefinition(self, rc.ReadbackSB, "ReadbackSB", rc.readbackSBDesc);

        try RenderRegistrySys.addBufferDefinition(self, rc.EntitySB, "EntitySB", rc.entitySBDesc);
        try RenderRegistrySys.addBufferDefinition(self, rc.MainCamUB, "MainCamUB", rc.mainCamUBDesc);
        try RenderRegistrySys.addBufferDefinition(self, rc.DebugCamUB, "DebugCamUB", rc.debugCamUBDesc);

        try RenderRegistrySys.addBufferDefinition(self, rc.ImguiVB, "ImguiVB", rc.imguiVBDesc);
        try RenderRegistrySys.addBufferDefinition(self, rc.ImguiIB, "ImguiIB", rc.imguiIBDesc);

        // Textures
        try RenderRegistrySys.addTextureDefinition(self, rc.RayMarchInputTex, "RayMarchInputTex", rc.rayMarchTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.RayMarchOutputTex, "RayMarchOutputTex", rc.rayMarchTexDesc);

        try RenderRegistrySys.addTextureDefinition(self, rc.GridTex, "GridTex", rc.gridTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.GridTexOutput, "GridTexOutput", rc.gridTexDesc);

        try RenderRegistrySys.addTextureDefinition(self, rc.GridDepthTex, "GridDepthTex", rc.gridDepthTexDesc);

        try RenderRegistrySys.addTextureDefinition(self, rc.DebugGridInputTex, "DebugGridInputTex", rc.debugGridTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.DebugGridOutputTex, "DebugGridOutputTex", rc.debugGridTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.DebugGridFinalOutputTex, "DebugGridFinalOutputTex", rc.debugGridTexDesc);

        try RenderRegistrySys.addTextureDefinition(self, rc.DebugGridDepthTex, "DebugGridDepthTex", rc.debugGridDepthTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.DebugGridDepthOutputTex, "DebugGridDepthOutputTex", rc.debugGridDepthTexDesc);

        try RenderRegistrySys.addTextureDefinition(self, rc.PlaneTex, "PlaneTex", rc.planeTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.PlaneOutputTex, "PlaneOutputTex", rc.planeTexDesc);

        try RenderRegistrySys.addTextureDefinition(self, rc.PlaneDepthTex, "PlaneDepthTex", rc.planeDepthTexDesc);

        try RenderRegistrySys.addTextureDefinition(self, rc.DebugPlaneInputTex, "DebugPlaneInputTex", rc.debugPlaneTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.DebugPlaneOutputTex, "DebugPlaneOutputTex", rc.debugPlaneTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.DebugPlaneOutputFrustumViewTex, "DebugPlaneOutputFrustumViewTex", rc.debugPlaneTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.DebugPlaneEditorGridOutputTex, "DebugPlaneEditorGridOutputTex", rc.debugPlaneTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.DebugPlaneDepthTex, "DebugPlaneDepthTex", rc.debugPlaneDepthTexDesc);

        try RenderRegistrySys.addTextureDefinition(self, rc.DepthViewTex, "DepthViewTex", rc.depthViewTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.DepthViewOutputTex, "DepthViewOutputTex", rc.depthViewTexDesc);

        try RenderRegistrySys.addTextureDefinition(self, rc.TestTileTex, "TestTileTex", rc.testTilesTexDesc);
        try RenderRegistrySys.addTextureDefinition(self, rc.ImguiFontTex, "ImguiFontTex", rc.imguiFontTexDesc);
    }
};
