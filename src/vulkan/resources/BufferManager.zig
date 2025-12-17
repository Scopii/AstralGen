const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const vkFn = @import("../modules/vk.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const VkAllocator = @import("vma.zig").VkAllocator;
const check = @import("error.zig").check;

pub const BufferManager = struct {};
