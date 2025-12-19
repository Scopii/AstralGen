const std = @import("std");
const Allocator = std.mem.Allocator;
const zm = @import("zmath");
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;

pub const Alignment = enum { left, right, top, bot, center, topRight, topLeft, botRight, botLeft, none };
pub const Ruleset = enum { rightRow, leftRow, topColumn, bottomColumn, none };

pub const Node = struct {
    pos: @Vector(2, u16),
    curPos: @Vector(2, u16) = .{ 0, 0 },
    extent: @Vector(2, u16),
    color: @Vector(4, u8),
    alignment: Alignment,
};

pub const Container = struct {
    nodeIDs: std.ArrayList(u32),
    offset: @Vector(2, u16),
    dimensions: @Vector(2, u16),
    ruleset: Ruleset,
    alignment: Alignment,
    parent: ?u32,

    pub fn init(alloc: Allocator, offset: @Vector(2, u16), dimensions: @Vector(2, u16), ruleset: Ruleset, alignment: Alignment, parent: ?u32) !Container {
        return .{
            .nodeIDs = std.ArrayList(u32).init(alloc),
            .offset = offset,
            .dimensions = dimensions,
            .ruleset = ruleset,
            .alignment = alignment,
            .parent = parent,
        };
    }

    pub fn deinit(self: *Container) void {
        self.nodeIDs.deinit();
    }

    pub fn addNode(self: *Container, nodeID: u32) !void {
        try self.nodeIDs.append(nodeID);
    }
};

pub const UiManager = struct {
    alloc: Allocator,
    windowSize: @Vector(2, u16) = .{ 1600, 900 },
    container: CreateMapArray(Container, 1000, u32, 1000, 0) = .{},
    nodes: CreateMapArray(Node, 10_000, u32, 10_000, 0) = .{},

    pub fn init(alloc: Allocator) !UiManager {
        return .{ .alloc = alloc };
    }

    pub fn startUi(self: *UiManager) !void {
        const containerCount = self.container.getNextFreeIndex();
        var baseContainer = try Container.init(self.alloc, .{ 100, 100 }, .{ 500, 500 }, .none, .none, null);
        self.container.set(containerCount, baseContainer);

        const node1 = Node{ .pos = .{ 100, 100 }, .extent = .{ 500, 500 }, .color = .{ 255, 255, 255, 255 }, .alignment = .none };
        const nodeCount = self.nodes.getNextFreeIndex();
        try baseContainer.addNode(nodeCount);
        self.nodes.set(nodeCount, node1);
    }

    pub fn calculateUi(self: *UiManager) void {
        for (self.container.getElements()) |container| {
            for (container.nodeIDs.items) |id| {
                // Just adding offset
                const nodePtr = self.nodes.getPtr(id);
                nodePtr.*.curPos = nodePtr.*.pos + container.offset;
            }
        }
    }
};
