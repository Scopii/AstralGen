const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const FrameGraphQueue = @import("FrameGraphQueue.zig").FrameGraphQueue;
const FrameGraphData = @import("FrameGraphData.zig").FrameGraphData;
const EngineData = @import("../EngineData.zig").EngineData;
const std = @import("std");

const ResourceRegistrySys = @import("0_resourceRegistry/ResourceRegistrySys.zig").ResourceRegistrySys;
const PassExtractorSys = @import("1_passExtractor/PassExtractorSys.zig").PassExtractorSys;
const ResourceExtractorSys = @import("2_resourceExtractor/ResourceExtractorSys.zig").ResourceExtractorSys;
const DependancyExtractorSys = @import("3_dependancyExtractor/DependancyExtractorSys.zig").DependancyExtractorSys;
const GraphExtractorSys = @import("4_graphExtractor/GraphExtractorSys.zig").GraphExtractorSys;
const GraphOptimizerSys = @import("4.5_graphOptimizer/GraphOptimizerSys.zig").GraphOptimizerSys;
const LifetimeExtractorSys = @import("5_lifetimeExtractor/LifetimeExtractorSys.zig").LifetimeExtractorSys;
const ResourceMapperSys = @import("5.1_resourceMapper/ResourceMapperSys.zig").ResourceMapperSys;
const LifetimeMergerSys = @import("5.2_lifetimeMerger/LifetimeMergerSys.zig").LifetimeMergerSys;
const GroupMergerSys = @import("5.4_groupMerger/GroupMergerSys.zig").GroupMergerSys;
const ResourceAssignerSys = @import("6_resourceAssigner/ResourceAssignerSys.zig").ResourceAssignerSys;
const MappingComparatorSys = @import("5.3_mappingComparator/MappingComparatorSys.zig").MappingComparatorSys;
const PassSorterSys = @import("7_passSorter/PassSorterSys.zig").PassSorterSys;

const pe = @import("components.zig");
const TexPassId = pe.TexPassId;
const BufPassId = pe.BufPassId;

const rc = @import("../.configs/renderConfig.zig");

const depthViewPass = @import("../.assets/passes/depthView/DepthView.zig").depthViewPass;

pub const FrameGraphSys = struct {
    pub fn init(graph: *FrameGraphData, alloc: std.mem.Allocator) !void {
        try ResourceRegistrySys.init(&graph.resourceRegistry, alloc);

        try ResourceRegistrySys.addPassDefinition(&graph.resourceRegistry, .id(0), depthViewPass);

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

        try ResourceExtractorSys.buildAccesses(&graph.resourceExtractor, &graph.passExtractor, &graph.resourceRegistry);

        try DependancyExtractorSys.buildDependencies(&graph.dependancyExtractor, &graph.resourceExtractor, &graph.passExtractor, &graph.resourceRegistry);

        try GraphExtractorSys.buildGraph(&graph.graphExtractor, &graph.dependancyExtractor, &graph.passExtractor, &graph.resourceRegistry);

        try GraphOptimizerSys.assignResourceLevels(&graph.graphOptimizer, &graph.graphExtractor, &graph.resourceExtractor, &graph.resourceRegistry);

        try LifetimeExtractorSys.assignResourceLifetimes(&graph.lifetimeExtractor, &graph.graphOptimizer, &graph.resourceExtractor, &graph.resourceRegistry);

        try ResourceMapperSys.buildMapping(&graph.resourceMapper, &graph.resourceExtractor, &graph.lifetimeExtractor, &graph.graphOptimizer, &graph.resourceRegistry);

        try LifetimeMergerSys.buildPassResources(&graph.lifetimeMerger, &graph.lifetimeExtractor, &graph.resourceMapper, &graph.resourceRegistry);

        try MappingComparatorSys.buildChanges(&graph.mappingComparator, &graph.resourceMapper, &graph.resourceRegistry);

        try GroupMergerSys.buildPassResources(&graph.groupMerger, &graph.resourceExtractor, &graph.lifetimeMerger, &graph.resourceMapper, &graph.resourceRegistry);

        try ResourceAssignerSys.buildPersistentResources(
            &graph.resourceAssigner,
            &graph.resourceExtractor,
            &graph.resourceMapper,
            &graph.mappingComparator,
            &graph.groupMerger,
            &graph.resourceRegistry,
            rendererQueue,
            memoryMan,
        );

        try PassSorterSys.buildFrame(&graph.passSorter, &graph.passExtractor, &graph.graphOptimizer, &graph.groupMerger, &graph.resourceAssigner, &graph.resourceRegistry);
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

    pub fn processQueue(frameGraph: *const FrameGraphData, frameGraphQueue: *FrameGraphQueue, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const arena = memoryMan.getGlobalArena();

        for (frameGraphQueue.get()) |event| {
            switch (event) {
                .updateBuffer => |updateBuffer| {
                    const bufKey: u16 = updateBuffer.bufPassId.val();
                    if (frameGraph.resourceAssigner.bufAssigns.isKeyUsed(bufKey) == false) return error.BufferEnumHasNoPhysicalID;
                    const bufId = frameGraph.resourceAssigner.bufAssigns.getByKey(bufKey);

                    const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBuffer");
                    const Payload = std.meta.Child(PayloadPtr);
                    const updateBufferPtr = try arena.create(Payload);
                    updateBufferPtr.* = .{ .bufId = bufId, .data = updateBuffer.data };

                    rendererQueue.append(.{ .updateBuffer = updateBufferPtr });
                    // std.debug.print("FrameGraph: Update Buffer ({}) send to Renderer\n", .{updateBuffer.bufEnum});
                },
                .updateBufferSegment => |updateBufferSegment| {
                    const bufKey: u16 = updateBufferSegment.bufPassId.val();
                    if (frameGraph.resourceAssigner.bufAssigns.isKeyUsed(bufKey) == false) return error.BufferEnumHasNoPhysicalID;
                    const bufId = frameGraph.resourceAssigner.bufAssigns.getByKey(bufKey);

                    const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBufferSegment");
                    const Payload = std.meta.Child(PayloadPtr);
                    const updateBufferSegmentPtr = try arena.create(Payload);
                    updateBufferSegmentPtr.* = .{ .bufId = bufId, .data = updateBufferSegment.data, .elementOffset = updateBufferSegment.elementOffset };

                    rendererQueue.append(.{ .updateBufferSegment = updateBufferSegmentPtr });
                    // std.debug.print("FrameGraph: Update Buffer Segment ({}) send to Renderer\n", .{updateBufferSegment.bufEnum});
                },
                .updateTexture => |updateTexture| {
                    const texKey: u16 = updateTexture.texPassId.val();
                    if (frameGraph.resourceAssigner.texAssigns.isKeyUsed(texKey) == false) return error.TextureEnumHasNoPhysicalID;
                    const texId = frameGraph.resourceAssigner.texAssigns.getByKey(texKey);

                    const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateTexture");
                    const Payload = std.meta.Child(PayloadPtr);
                    const updateTexturePtr = try arena.create(Payload);
                    updateTexturePtr.* = .{ .texId = texId, .data = updateTexture.data, .newExtent = updateTexture.newExtent };

                    rendererQueue.append(.{ .updateTexture = updateTexturePtr });
                    // std.debug.print("FrameGraph: Update Texture ({}) send to Renderer\n", .{updateTexture.texEnum});
                },
            }
        }
        frameGraphQueue.clear();
    }
};
