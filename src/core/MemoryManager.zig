const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MemoryManager = struct {
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator, // adding FixedBufferAllocator?

    pub fn init(baseAllocator: Allocator) MemoryManager {
        return .{
            .alloc = baseAllocator,
            .arena = std.heap.ArenaAllocator.init(baseAllocator),
        };
    }

    pub fn deinit(self: *MemoryManager) void {
        self.arena.deinit();
    }

    pub fn getAllocator(self: *MemoryManager) std.mem.Allocator {
        return self.alloc;
    }

    pub fn getGlobalArena(self: *MemoryManager) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn createArena(self: *MemoryManager) std.heap.ArenaAllocator {
        return std.heap.ArenaAllocator.init(self.alloc);
    }

    pub fn resetArena(self: *MemoryManager) void {
        _ = self.arena.reset(.free_all);
    }
};
