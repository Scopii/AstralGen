const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MemoryManager = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator, // adding FixedBufferAllocator?

    pub fn init(baseAllocator: Allocator) !MemoryManager {
        const arena = std.heap.ArenaAllocator.init(baseAllocator);

        return .{
            .allocator = baseAllocator,
            .arena = arena,
        };
    }

    pub fn getAllocator(self: *MemoryManager) std.mem.Allocator {
        return self.allocator;
    }

    pub fn getGlobalArena(self: *MemoryManager) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn createArena(self: *MemoryManager) std.heap.ArenaAllocator {
        return std.heap.ArenaAllocator.init(self.allocator);
    }

    pub fn resetArena(self: *MemoryManager) void {
        _ = self.arena.reset(.free_all);
    }

    pub fn deinit(self: *MemoryManager) void {
        self.arena.deinit();
    }
};
