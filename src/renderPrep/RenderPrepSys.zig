const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const EntityData = @import("../ecs/EntityData.zig").EntityData;
const GpuObjectData = @import("../render/help/Types.zig").GpuObjectData;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const RenderPrepSys = struct {
    pub fn extractEntities(ecs: *EntityData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const entityCount = ecs.renderables.getLength();
        if (entityCount == 0) return;

        // Allocate the dense array for this frame
        const arena = memoryMan.getGlobalArena();
        const gpuDataArray = try arena.alloc(GpuObjectData, entityCount);

        var isDirty = false;

        // Join ECS components and pack them into the dense array
        for (0..entityCount) |i| {
            const entityId = ecs.renderables.getKeyByIndex(@intCast(i));
            const renderable = ecs.renderables.getByIndex(@intCast(i));

            if (!ecs.transforms.isKeyUsed(entityId)) continue;
            const transform = ecs.transforms.getPtrByKey(entityId);

            if (isDirty == false and transform.isDirty == true) isDirty = true;
            transform.isDirty = false;

            gpuDataArray[i] = .{
                .posAndSize = .{ transform.pos[0], transform.pos[1], transform.pos[2], renderable.size },
                .colorAndSdf = .{ renderable.colorR, renderable.colorG, renderable.colorB, @floatFromInt(@intFromEnum(renderable.sdfId)) },
            };
        }

        if (isDirty == false) return;

        // Send the packed, dense array to the Renderer Queue
        const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBuffer");
        const Payload = std.meta.Child(PayloadPtr);
        const updateBufferPtr = try arena.create(Payload);

        updateBufferPtr.* = .{ .bufId = rc.objectSB.id, .data = std.mem.sliceAsBytes(gpuDataArray) };

        rendererQueue.append(.{ .updateBuffer = updateBufferPtr });
    }

    pub fn extractEntity(ecs: *EntityData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const entityCount = ecs.renderables.getLength();
        if (entityCount == 0) return;

        // Allocate the dense array for this frame
        const arena = memoryMan.getGlobalArena();

        // Join ECS components and pack them into the dense array
        for (0..entityCount) |i| {
            const gpuData = try arena.create(GpuObjectData);

            const entityId = ecs.renderables.getKeyByIndex(@intCast(i));
            const renderable = ecs.renderables.getByIndex(@intCast(i));

            if (!ecs.transforms.isKeyUsed(entityId)) continue;
            const transform = ecs.transforms.getPtrByKey(entityId);

            if (transform.isDirty == false) continue;
            transform.isDirty = false;

            gpuData.* = .{
                .posAndSize = .{ transform.pos[0], transform.pos[1], transform.pos[2], renderable.size },
                .colorAndSdf = .{ renderable.colorR, renderable.colorG, renderable.colorB, @floatFromInt(@intFromEnum(renderable.sdfId)) },
            };

            // Send the packed, dense array to the Renderer Queue
            const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBufferSegment");
            const Payload = std.meta.Child(PayloadPtr);
            const updateBufferSegmentPtr = try arena.create(Payload);

            updateBufferSegmentPtr.* = .{ .bufId = rc.objectSB.id, .data = std.mem.asBytes(gpuData), .elementOffset = @intCast(i) };

            rendererQueue.append(.{ .updateBufferSegment = updateBufferSegmentPtr });
        }
    }
};
