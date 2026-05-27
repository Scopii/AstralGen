const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const FrameGraphQueue = @import("FrameGraphQueue.zig").FrameGraphQueue;
const FrameGraphData = @import("FrameGraphData.zig").FrameGraphData;
const EngineData = @import("../EngineData.zig").EngineData;
const pe = @import("enums.zig");
const std = @import("std");

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

const TextureEnum = pe.TextureEnum;
const BufferEnum = pe.BufferEnum;
const PassEnum = pe.PassEnum;

pub const FrameGraphSys = struct {
    pub fn build(frameGraph: *FrameGraphData, data: *const EngineData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        PassExtractorSys.build(&frameGraph.passExtractor, data);

        try ResourceExtractorSys.buildAccesses(&frameGraph.resourceExtractor, &frameGraph.passExtractor);

        DependancyExtractorSys.buildDependencies(&frameGraph.dependancyExtractor, &frameGraph.resourceExtractor);

        try GraphExtractorSys.buildGraph(&frameGraph.graphExtractor, &frameGraph.dependancyExtractor, &frameGraph.passExtractor);

        try GraphOptimizerSys.assignResourceLevels(&frameGraph.graphOptimizer, &frameGraph.graphExtractor, &frameGraph.resourceExtractor);

        LifetimeExtractorSys.assignResourceLifetimes(&frameGraph.lifetimeExtractor, &frameGraph.graphOptimizer, &frameGraph.resourceExtractor);

        try ResourceMapperSys.buildMapping(&frameGraph.resourceMapper, &frameGraph.resourceExtractor, &frameGraph.lifetimeExtractor, &frameGraph.graphOptimizer);

        LifetimeMergerSys.buildPassResources(&frameGraph.lifetimeMerger, &frameGraph.lifetimeExtractor, &frameGraph.resourceMapper);

        MappingComparatorSys.buildChanges(&frameGraph.mappingComparator, &frameGraph.resourceMapper);

        GroupMergerSys.buildPassResources(&frameGraph.groupMerger, &frameGraph.lifetimeMerger, &frameGraph.resourceMapper);

        try ResourceAssignerSys.buildPersistentResources(
            &frameGraph.resourceAssigner,
            &frameGraph.resourceMapper,
            &frameGraph.mappingComparator,
            &frameGraph.groupMerger,
            rendererQueue,
            memoryMan,
        );

        try PassSorterSys.buildFrame(&frameGraph.passSorter, &frameGraph.passExtractor, &frameGraph.graphOptimizer, &frameGraph.groupMerger, &frameGraph.resourceAssigner);
    }

    pub fn createTextureManually(frameGraph: *FrameGraphData, texEnum: TextureEnum, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        try ResourceAssignerSys.createTexture(&frameGraph.resourceAssigner, &frameGraph.resourceMapper, texEnum, rendererQueue, memoryMan, .manuel);
    }

    pub fn deleteTextureManually(frameGraph: *FrameGraphData, texEnum: TextureEnum, rendererQueue: *RendererQueue) void {
        ResourceAssignerSys.deleteTexture(&frameGraph.resourceAssigner, texEnum, rendererQueue, .manuel);
    }

    pub fn createBufferManually(frameGraph: *FrameGraphData, bufEnum: BufferEnum, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        try ResourceAssignerSys.createBuffer(&frameGraph.resourceAssigner, &frameGraph.resourceMapper, bufEnum, rendererQueue, memoryMan, .manuel);
    }

    pub fn deleteBufferManually(frameGraph: *FrameGraphData, bufEnum: BufferEnum, rendererQueue: *RendererQueue) void {
        ResourceAssignerSys.deleteBuffer(&frameGraph.resourceAssigner, bufEnum, rendererQueue, .manuel);
    }

    pub fn processQueue(frameGraph: *const FrameGraphData, frameGraphQueue: *FrameGraphQueue, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const arena = memoryMan.getGlobalArena();

        for (frameGraphQueue.get()) |event| {
            switch (event) {
                .updateBuffer => |updateBuffer| {
                    const bufKey: u16 = @intFromEnum(updateBuffer.bufEnum);
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
                    const bufKey: u16 = @intFromEnum(updateBufferSegment.bufEnum);
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
                    const texKey: u16 = @intFromEnum(updateTexture.texEnum);
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
