const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const FrameGraphQueue = @import("FrameGraphQueue.zig").FrameGraphQueue;
const FrameGraphData = @import("FrameGraphData.zig").FrameGraphData;
const EngineData = @import("../EngineData.zig").EngineData;
const rc = @import("../.configs/renderConfig.zig");
const UiData = @import("../ui/UiData.zig").UiData;
const ic = @import("../.configs/idConfig.zig");
const std = @import("std");
const TexPassId = ic.TexPassId;
const BufPassId = ic.BufPassId;
const BufId = ic.BufId;
const TexId = ic.TexId;

const RegistrySys = @import("0_Registry/RegistrySys.zig").RegistrySys;
const PassSys = @import("1_Pass/PassSys.zig").PassSys;
const AccessSys = @import("1.5_Access/AccessSys.zig").AccessSys;
const ResourceSys = @import("2_Resource/ResourceSys.zig").ResourceSys;
const DependancySys = @import("3_Dependancy/DependancySys.zig").DependancySys;
const GraphSys = @import("4_Graph/GraphSys.zig").GraphSys;
const OptimizerSys = @import("4.5_Optimizer/OptimizerSys.zig").OptimizerSys;
const LifetimeSys = @import("5_Lifetime/LifetimeSys.zig").LifetimeSys;
const MapperSys = @import("5.1_Mapper/MapperSys.zig").MapperSys;
const MergerSys = @import("5.2_Merger/MergerSys.zig").MergerSys;
const ComparatorSys = @import("5.3_Comparator/ComparatorSys.zig").ComparatorSys;
const GroupSys = @import("5.4_Group/GroupSys.zig").GroupSys;
const AssignerSys = @import("6_Assigner/AssignerSys.zig").AssignerSys;
const SorterSys = @import("7_Sorter/SorterSys.zig").SorterSys;

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

pub const FrameGraphSys = struct {
    pub fn init(graph: *FrameGraphData, alloc: std.mem.Allocator) !void {
        try RegistrySys.init(&graph.registry, alloc);

        try RegistrySys.addPassDefinition(&graph.registry, .id(0), depthViewPass);
        try RegistrySys.addPassDefinition(&graph.registry, .id(1), compRayMarchPass);
        try RegistrySys.addPassDefinition(&graph.registry, .id(2), editorGridGridDebugPass);
        try RegistrySys.addPassDefinition(&graph.registry, .id(3), editorGridPlaneDebugPass);
        try RegistrySys.addPassDefinition(&graph.registry, .id(4), frustumViewPass);
        try RegistrySys.addPassDefinition(&graph.registry, .id(5), quantGridPass);
        try RegistrySys.addPassDefinition(&graph.registry, .id(6), quantGridDebugPass);
        try RegistrySys.addPassDefinition(&graph.registry, .id(7), quantPlanePass);
        try RegistrySys.addPassDefinition(&graph.registry, .id(8), quantPlaneDebugPass);
        try RegistrySys.addPassDefinition(&graph.registry, .id(9), quantCompPass);

        // Buffers
        try RegistrySys.addBufferDefinition(&graph.registry, rc.QuantIndirectInputSB, "QuantIndirectInputSB", rc.indirectSBDesc);
        try RegistrySys.addBufferDefinition(&graph.registry, rc.QuantIndirectOutputSB, "QuantIndirectOutputSB", rc.indirectSBDesc);
        try RegistrySys.addBufferDefinition(&graph.registry, rc.ReadbackSB, "ReadbackSB", rc.readbackSBDesc);

        try RegistrySys.addBufferDefinition(&graph.registry, rc.EntitySB, "EntitySB", rc.entitySBDesc);
        try RegistrySys.addBufferDefinition(&graph.registry, rc.MainCamUB, "MainCamUB", rc.mainCamUBDesc);
        try RegistrySys.addBufferDefinition(&graph.registry, rc.DebugCamUB, "DebugCamUB", rc.debugCamUBDesc);

        try RegistrySys.addBufferDefinition(&graph.registry, rc.ImguiVB, "ImguiVB", rc.imguiVBDesc);
        try RegistrySys.addBufferDefinition(&graph.registry, rc.ImguiIB, "ImguiIB", rc.imguiIBDesc);

        // Textures
        try RegistrySys.addTextureDefinition(&graph.registry, rc.RayMarchInputTex, "RayMarchInputTex", rc.rayMarchTexDesc);

        try RegistrySys.addTextureDefinition(&graph.registry, rc.GridTex, "GridTex", rc.gridTexDesc);
        try RegistrySys.addTextureDefinition(&graph.registry, rc.GridDepthTex, "GridDepthTex", rc.gridDepthTexDesc);

        try RegistrySys.addTextureDefinition(&graph.registry, rc.DebugGridInputTex, "DebugGridInputTex", rc.debugGridTexDesc);
        try RegistrySys.addTextureDefinition(&graph.registry, rc.DebugGridOutputTex, "DebugGridOutputTex", rc.debugGridTexDesc);

        try RegistrySys.addTextureDefinition(&graph.registry, rc.DebugGridDepthTex, "DebugGridDepthTex", rc.debugGridDepthTexDesc);
        try RegistrySys.addTextureDefinition(&graph.registry, rc.DebugGridDepthOutputTex, "DebugGridDepthOutputTex", rc.debugGridDepthTexDesc);

        try RegistrySys.addTextureDefinition(&graph.registry, rc.PlaneTex, "PlaneTex", rc.planeTexDesc);
        try RegistrySys.addTextureDefinition(&graph.registry, rc.PlaneDepthTex, "PlaneDepthTex", rc.planeDepthTexDesc);

        try RegistrySys.addTextureDefinition(&graph.registry, rc.DebugPlaneInputTex, "DebugPlaneInputTex", rc.debugPlaneTexDesc);
        try RegistrySys.addTextureDefinition(&graph.registry, rc.DebugPlaneOutputTex, "DebugPlaneOutputTex", rc.debugPlaneTexDesc);
        try RegistrySys.addTextureDefinition(&graph.registry, rc.DebugPlaneOutputFrustumViewTex, "DebugPlaneOutputFrustumViewTex", rc.debugPlaneTexDesc);
        try RegistrySys.addTextureDefinition(&graph.registry, rc.DebugPlaneDepthTex, "DebugPlaneDepthTex", rc.debugPlaneDepthTexDesc);

        try RegistrySys.addTextureDefinition(&graph.registry, rc.DepthViewTex, "DepthViewTex", rc.depthViewTexDesc);

        try RegistrySys.addTextureDefinition(&graph.registry, rc.TestTileTex, "TestTileTex", rc.testTilesTexDesc);
        try RegistrySys.addTextureDefinition(&graph.registry, rc.ImguiFontTex, "ImguiFontTex", rc.imguiFontTexDesc);
    }

    pub fn deinit(graph: *FrameGraphData) void {
        RegistrySys.deinit(&graph.registry);
    }

    pub fn build(graph: *FrameGraphData, data: *const EngineData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        try PassSys.newBuild(&graph.pass, &graph.registry, data);

        try AccessSys.buildAccesses(&graph.access, &graph.pass, &graph.registry);

        try ResourceSys.buildResources(&graph.resource, &graph.access, &graph.pass, &graph.registry);

        try DependancySys.buildDependencies(&graph.dependancy, &graph.access, &graph.registry);

        try GraphSys.buildGraph(&graph.graph, &graph.dependancy, &graph.pass, &graph.registry);

        try OptimizerSys.assignResourceLevels(&graph.optimizer, &graph.graph, &graph.access, &graph.resource, &graph.registry);

        try LifetimeSys.assignResourceLifetimes(&graph.lifetime, &graph.optimizer, &graph.access, &graph.registry);

        try MapperSys.buildMapping(&graph.mapper, &graph.access, &graph.resource, &graph.lifetime, &graph.optimizer, &graph.registry);

        try MergerSys.buildPassResources(&graph.merger, &graph.lifetime, &graph.mapper, &graph.registry);

        // const start = std.time.nanoTimestamp();
        // const end = std.time.nanoTimestamp();
        // std.debug.print("Merger Build: {d:.3} ns\n", .{@as(f64, @floatFromInt(end - start)) / 1_000.0});

        try ComparatorSys.buildChanges(&graph.comparator, &graph.mapper, &graph.registry);

        try GroupSys.buildPassResources(&graph.group, &graph.merger, &graph.mapper, &graph.registry);

        try AssignerSys.buildPersistentResources(&graph.assigner, &graph.mapper, &graph.comparator, &graph.group, &graph.registry, rendererQueue, memoryMan);

        try SorterSys.buildFrame(&graph.sorter, &graph.pass, &graph.optimizer, &graph.group, &graph.assigner, &graph.registry);
    }

    pub fn createTextureManually(frameGraph: *FrameGraphData, texPassId: TexPassId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        try AssignerSys.createTexture(&frameGraph.assigner, &frameGraph.mapper, &frameGraph.registry, texPassId, rendererQueue, memoryMan, .manuel);
    }

    pub fn deleteTextureManually(frameGraph: *FrameGraphData, texPassId: TexPassId, rendererQueue: *RendererQueue) void {
        AssignerSys.deleteTexture(&frameGraph.assigner, &frameGraph.registry, texPassId, rendererQueue, .manuel);
    }

    pub fn createBufferManually(frameGraph: *FrameGraphData, bufPassId: BufPassId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        try AssignerSys.createBuffer(&frameGraph.assigner, &frameGraph.mapper, &frameGraph.registry, bufPassId, rendererQueue, memoryMan, .manuel);
    }

    pub fn deleteBufferManually(frameGraph: *FrameGraphData, bufPassId: BufPassId, rendererQueue: *RendererQueue) void {
        AssignerSys.deleteBuffer(&frameGraph.assigner, &frameGraph.registry, bufPassId, rendererQueue, .manuel);
    }

    pub fn getBufHardwareId(frameGraph: *const FrameGraphData, name: []const u8) !BufId {
        const bufPassId = try frameGraph.registry.getBufferPassId(name);
        const hardwareBufId = frameGraph.assigner.bufAssigns.getByKey(bufPassId);
        return hardwareBufId;
    }

    pub fn getTexHardwareId(frameGraph: *const FrameGraphData, name: []const u8) !TexId {
        const texPassId = try frameGraph.registry.getTexturePassId(name);
        const hardwareTexId = frameGraph.assigner.texAssigns.getByKey(texPassId);
        return hardwareTexId;
    }

    pub fn fillUiHardwareIds(frameGraph: *const FrameGraphData, uiData: *UiData) !void { // UiData not const!?
        for (uiData.uiNodes.slice()) |*uiNode| {
            if (uiNode.imguiVB != .bufName) return error.UiImguiVBNeedsToBeNameForResolve;
            if (uiNode.imguiIB != .bufName) return error.UiImguiIBNeedsToBeNameForResolve;

            const imguiVBHardwareID = try getBufHardwareId(frameGraph, uiNode.imguiVB.bufName);
            const imguiIBHardwareID = try getBufHardwareId(frameGraph, uiNode.imguiIB.bufName);

            uiNode.imguiVB = .{ .bufId = imguiVBHardwareID };
            uiNode.imguiIB = .{ .bufId = imguiIBHardwareID };
        }

        for (uiData.uiDraws.slice()) |*uiDraw| {
            if (uiDraw.drawTex != .texName) return error.UiImguiDrawTexNeedsToBeNameForResolve;
            const imguiTexHardwareID = try getTexHardwareId(frameGraph, uiDraw.drawTex.texName);
            uiDraw.drawTex = .{ .texId = imguiTexHardwareID };
        }
    }

    pub fn processQueue(frameGraph: *const FrameGraphData, frameGraphQueue: *FrameGraphQueue, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const arena = memoryMan.getGlobalArena();

        for (frameGraphQueue.get()) |event| {
            switch (event) {
                .updateBuffer => |updateBuffer| {
                    const hardwareId: BufId = switch (updateBuffer.bufUnion) {
                        .bufId => |bufId| bufId,
                        .bufName => |bufName| try getBufHardwareId(frameGraph, bufName),
                        .bufPassId => |bufPassId| frameGraph.assigner.bufAssigns.getByKey(bufPassId),
                    };

                    const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBuffer");
                    const Payload = std.meta.Child(PayloadPtr);
                    const updateBufferPtr = try arena.create(Payload);
                    updateBufferPtr.* = .{ .bufId = hardwareId, .data = updateBuffer.data };

                    rendererQueue.append(.{ .updateBuffer = updateBufferPtr });
                    // std.debug.print("FrameGraph: Update Buffer ({}) send to Renderer\n", .{updateBuffer.bufEnum});
                },
                .updateBufferSegment => |updateBufferSegment| {
                    const hardwareId: BufId = switch (updateBufferSegment.bufUnion) {
                        .bufId => |bufId| bufId,
                        .bufName => |bufName| try getBufHardwareId(frameGraph, bufName),
                        .bufPassId => |bufPassId| frameGraph.assigner.bufAssigns.getByKey(bufPassId),
                    };

                    const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBufferSegment");
                    const Payload = std.meta.Child(PayloadPtr);
                    const updateBufferSegmentPtr = try arena.create(Payload);
                    updateBufferSegmentPtr.* = .{ .bufId = hardwareId, .data = updateBufferSegment.data, .elementOffset = updateBufferSegment.elementOffset };

                    rendererQueue.append(.{ .updateBufferSegment = updateBufferSegmentPtr });
                    // std.debug.print("FrameGraph: Update Buffer Segment ({}) send to Renderer\n", .{updateBufferSegment.bufEnum});
                },
                .updateTexture => |updateTexture| {
                    const hardwareId: TexId = switch (updateTexture.texUnion) {
                        .texId => |texId| texId,
                        .texName => |texName| try getTexHardwareId(frameGraph, texName),
                        .texPassId => |texPassId| frameGraph.assigner.texAssigns.getByKey(texPassId),
                    };

                    const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateTexture");
                    const Payload = std.meta.Child(PayloadPtr);
                    const updateTexturePtr = try arena.create(Payload);
                    updateTexturePtr.* = .{ .texId = hardwareId, .data = updateTexture.data, .newExtent = updateTexture.newExtent };

                    rendererQueue.append(.{ .updateTexture = updateTexturePtr });
                    // std.debug.print("FrameGraph: Update Texture ({}) send to Renderer\n", .{updateTexture.texEnum});
                },
            }
        }
        frameGraphQueue.clear();
    }
};
