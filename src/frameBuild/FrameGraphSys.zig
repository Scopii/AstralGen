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

const ResourceRegistrySys = @import("0_resourceRegistry/ResourceRegistrySys.zig").ResourceRegistrySys;
const PassExtractorSys = @import("1_passExtractor/PassExtractorSys.zig").PassExtractorSys;
const AccessExtractorSys = @import("1.5_accessExtractor/AccessExtractorSys.zig").AccessExtractorSys;
const ResourceExtractorSys = @import("2_resourceExtractor/ResourceExtractorSys.zig").ResourceExtractorSys;
const DependancyExtractorSys = @import("3_dependancyExtractor/DependancyExtractorSys.zig").DependancyExtractorSys;
const GraphExtractorSys = @import("4_graphExtractor/GraphExtractorSys.zig").GraphExtractorSys;
const GraphOptimizerSys = @import("4.5_graphOptimizer/GraphOptimizerSys.zig").GraphOptimizerSys;
const LifetimeExtractorSys = @import("5_lifetimeExtractor/LifetimeExtractorSys.zig").LifetimeExtractorSys;
const ResourceMapperSys = @import("5.1_resourceMapper/ResourceMapperSys.zig").ResourceMapperSys;
const LifetimeMergerSys = @import("5.2_lifetimeMerger/LifetimeMergerSys.zig").LifetimeMergerSys;
const MappingComparatorSys = @import("5.3_mappingComparator/MappingComparatorSys.zig").MappingComparatorSys;
const GroupMergerSys = @import("5.4_groupMerger/GroupMergerSys.zig").GroupMergerSys;
const ResourceAssignerSys = @import("6_resourceAssigner/ResourceAssignerSys.zig").ResourceAssignerSys;
const PassSorterSys = @import("7_passSorter/PassSorterSys.zig").PassSorterSys;

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
        try ResourceRegistrySys.init(&graph.resourceRegistry, alloc);

        try ResourceRegistrySys.addPassDefinition(&graph.resourceRegistry, .id(0), depthViewPass);
        try ResourceRegistrySys.addPassDefinition(&graph.resourceRegistry, .id(1), compRayMarchPass);
        try ResourceRegistrySys.addPassDefinition(&graph.resourceRegistry, .id(2), editorGridGridDebugPass);
        try ResourceRegistrySys.addPassDefinition(&graph.resourceRegistry, .id(3), editorGridPlaneDebugPass);
        try ResourceRegistrySys.addPassDefinition(&graph.resourceRegistry, .id(4), frustumViewPass);
        try ResourceRegistrySys.addPassDefinition(&graph.resourceRegistry, .id(5), quantGridPass);
        try ResourceRegistrySys.addPassDefinition(&graph.resourceRegistry, .id(6), quantGridDebugPass);
        try ResourceRegistrySys.addPassDefinition(&graph.resourceRegistry, .id(7), quantPlanePass);
        try ResourceRegistrySys.addPassDefinition(&graph.resourceRegistry, .id(8), quantPlaneDebugPass);
        try ResourceRegistrySys.addPassDefinition(&graph.resourceRegistry, .id(9), quantCompPass);

        // Buffers
        try ResourceRegistrySys.addBufferDefinition(&graph.resourceRegistry, rc.QuantIndirectInputSB, "QuantIndirectInputSB", rc.indirectSBDesc);
        try ResourceRegistrySys.addBufferDefinition(&graph.resourceRegistry, rc.QuantIndirectOutputSB, "QuantIndirectOutputSB", rc.indirectSBDesc);
        try ResourceRegistrySys.addBufferDefinition(&graph.resourceRegistry, rc.ReadbackSB, "ReadbackSB", rc.readbackSBDesc);

        try ResourceRegistrySys.addBufferDefinition(&graph.resourceRegistry, rc.EntitySB, "EntitySB", rc.entitySBDesc);
        try ResourceRegistrySys.addBufferDefinition(&graph.resourceRegistry, rc.MainCamUB, "MainCamUB", rc.mainCamUBDesc);
        try ResourceRegistrySys.addBufferDefinition(&graph.resourceRegistry, rc.DebugCamUB, "DebugCamUB", rc.debugCamUBDesc);

        try ResourceRegistrySys.addBufferDefinition(&graph.resourceRegistry, rc.ImguiVB, "ImguiVB", rc.imguiVBDesc);
        try ResourceRegistrySys.addBufferDefinition(&graph.resourceRegistry, rc.ImguiIB, "ImguiIB", rc.imguiIBDesc);

        // Textures
        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.RayMarchInputTex, "RayMarchInputTex", rc.rayMarchTexDesc);

        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.GridTex, "GridTex", rc.gridTexDesc);
        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.GridDepthTex, "GridDepthTex", rc.gridDepthTexDesc);

        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.DebugGridInputTex, "DebugGridInputTex", rc.debugGridTexDesc);
        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.DebugGridOutputTex, "DebugGridOutputTex", rc.debugGridTexDesc);

        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.DebugGridDepthTex, "DebugGridDepthTex", rc.debugGridDepthTexDesc);
        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.DebugGridDepthOutputTex, "DebugGridDepthOutputTex", rc.debugGridDepthTexDesc);

        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.PlaneTex, "PlaneTex", rc.planeTexDesc);
        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.PlaneDepthTex, "PlaneDepthTex", rc.planeDepthTexDesc);

        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.DebugPlaneInputTex, "DebugPlaneInputTex", rc.debugPlaneTexDesc);
        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.DebugPlaneOutputTex, "DebugPlaneOutputTex", rc.debugPlaneTexDesc);
        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.DebugPlaneOutputFrustumViewTex, "DebugPlaneOutputFrustumViewTex", rc.debugPlaneTexDesc);
        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.DebugPlaneDepthTex, "DebugPlaneDepthTex", rc.debugPlaneDepthTexDesc);

        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.DepthViewTex, "DepthViewTex", rc.depthViewTexDesc);

        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.TestTileTex, "TestTileTex", rc.testTilesTexDesc);
        try ResourceRegistrySys.addTextureDefinition(&graph.resourceRegistry, rc.ImguiFontTex, "ImguiFontTex", rc.imguiFontTexDesc);
    }

    pub fn deinit(graph: *FrameGraphData) void {
        ResourceRegistrySys.deinit(&graph.resourceRegistry);
    }

    pub fn build(graph: *FrameGraphData, data: *const EngineData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        try PassExtractorSys.newBuild(&graph.passExtractor, &graph.resourceRegistry, data);

        try AccessExtractorSys.buildAccesses(&graph.accessExtractor, &graph.passExtractor, &graph.resourceRegistry);

        try ResourceExtractorSys.buildResources(&graph.resourceExtractor, &graph.accessExtractor, &graph.passExtractor, &graph.resourceRegistry);

        try DependancyExtractorSys.buildDependencies(&graph.dependancyExtractor, &graph.accessExtractor, &graph.resourceRegistry);

        try GraphExtractorSys.buildGraph(&graph.graphExtractor, &graph.dependancyExtractor, &graph.passExtractor, &graph.resourceRegistry);

        try GraphOptimizerSys.assignResourceLevels(&graph.graphOptimizer, &graph.graphExtractor, &graph.accessExtractor, &graph.resourceExtractor, &graph.resourceRegistry);

        try LifetimeExtractorSys.assignResourceLifetimes(&graph.lifetimeExtractor, &graph.graphOptimizer, &graph.accessExtractor, &graph.resourceRegistry);

        try ResourceMapperSys.buildMapping(&graph.resourceMapper, &graph.accessExtractor, &graph.resourceExtractor, &graph.lifetimeExtractor, &graph.graphOptimizer, &graph.resourceRegistry);

        try LifetimeMergerSys.buildPassResources(&graph.lifetimeMerger, &graph.lifetimeExtractor, &graph.resourceMapper, &graph.resourceRegistry);

        try MappingComparatorSys.buildChanges(&graph.mappingComparator, &graph.resourceMapper, &graph.resourceRegistry);

        try GroupMergerSys.buildPassResources(&graph.groupMerger, &graph.lifetimeMerger, &graph.resourceMapper, &graph.resourceRegistry);

        try ResourceAssignerSys.buildPersistentResources(
            &graph.resourceAssigner,
            &graph.resourceMapper,
            &graph.mappingComparator,
            &graph.groupMerger,
            &graph.resourceRegistry,
            rendererQueue,
            memoryMan,
        );

        try PassSorterSys.buildFrame(
            &graph.passSorter,
            &graph.passExtractor,
            &graph.graphOptimizer,
            &graph.groupMerger,
            &graph.resourceAssigner,
            &graph.resourceRegistry,
        );
    }

    pub fn createTextureManually(frameGraph: *FrameGraphData, texPassId: TexPassId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        try ResourceAssignerSys.createTexture(&frameGraph.resourceAssigner, &frameGraph.resourceMapper, &frameGraph.resourceRegistry, texPassId, rendererQueue, memoryMan, .manuel);
    }

    pub fn deleteTextureManually(frameGraph: *FrameGraphData, texPassId: TexPassId, rendererQueue: *RendererQueue) void {
        ResourceAssignerSys.deleteTexture(&frameGraph.resourceAssigner, &frameGraph.resourceRegistry, texPassId, rendererQueue, .manuel);
    }

    pub fn createBufferManually(frameGraph: *FrameGraphData, bufPassId: BufPassId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        try ResourceAssignerSys.createBuffer(&frameGraph.resourceAssigner, &frameGraph.resourceMapper, &frameGraph.resourceRegistry, bufPassId, rendererQueue, memoryMan, .manuel);
    }

    pub fn deleteBufferManually(frameGraph: *FrameGraphData, bufPassId: BufPassId, rendererQueue: *RendererQueue) void {
        ResourceAssignerSys.deleteBuffer(&frameGraph.resourceAssigner, &frameGraph.resourceRegistry, bufPassId, rendererQueue, .manuel);
    }

    pub fn getBufHardwareId(frameGraph: *const FrameGraphData, name: []const u8) !BufId {
        const bufPassId = try frameGraph.resourceRegistry.getBufferPassId(name);
        const hardwareBufId = frameGraph.resourceAssigner.bufAssigns.getByKey(bufPassId.val());
        return hardwareBufId;
    }

    pub fn getTexHardwareId(frameGraph: *const FrameGraphData, name: []const u8) !TexId {
        const texPassId = try frameGraph.resourceRegistry.getTexturePassId(name);
        const hardwareTexId = frameGraph.resourceAssigner.texAssigns.getByKey(texPassId.val());
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
                        .bufPassId => |bufPassId| frameGraph.resourceAssigner.bufAssigns.getByKey(bufPassId.val()),
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
                        .bufPassId => |bufPassId| frameGraph.resourceAssigner.bufAssigns.getByKey(bufPassId.val()),
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
                        .texPassId => |texPassId| frameGraph.resourceAssigner.texAssigns.getByKey(texPassId.val()),
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
