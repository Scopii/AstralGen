const ResourceRegistry = @import("ResourceRegistry.zig").ResourceRegistry;
const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const ResourceUpdater = @import("ResourceUpdater.zig").ResourceUpdater;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const ResourceQueue = @import("ResourceQueue.zig").ResourceQueue;
const DescriptorMan = @import("DescriptorMan.zig").DescriptorMan;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../.configs/renderConfig.zig");
const Context = @import("Context.zig").Context;
const vk = @import("../../.modules/vk.zig").c;
const vhT = @import("../help/Types.zig");
const vhE = @import("../help/Enums.zig");
const Allocator = std.mem.Allocator;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

pub fn checkBufferResize(resize: vhE.ResizeType, newSize: u64, oldSize: u64) !bool {
    return switch (resize) {
        .Block => if (newSize > oldSize) error.BufferBaseTooSmallForUpdate else false,
        .Grow => newSize > oldSize,
        .Fit => newSize != oldSize,
    };
}

pub fn checkTextureResize(resize: vhE.ResizeType, old: vk.VkExtent3D, new: vk.VkExtent3D) !bool {
    return switch (resize) {
        .Block => if (old.width != new.width or old.height != new.height or old.depth != new.depth ) return error.TextureResizeNotAllowedOnBlock else false,
        .Grow => old.width < new.width or old.height < new.height or old.depth < new.depth,
        .Fit => old.width != new.width or old.height != new.height or old.depth != new.depth,
    };
}

pub fn convertToByteSlice(data: anytype) ![]const u8 {
    const DataType = @TypeOf(data);
    return switch (@typeInfo(DataType)) {
        .optional => if (data) |d| convertToByteSlice(d) else error.ExpectedPointer,
        .pointer => |ptr| switch (ptr.size) {
            .one => std.mem.asBytes(data),
            .slice => std.mem.sliceAsBytes(data),
            else => return error.UnsupportedPointerType,
        },
        else => return error.ExpectedPointer,
    };
}

pub fn InfOfId(comptime T: type) type {
    return switch (T) {
        BufferMeta.BufId => BufferMeta.BufInf,
        TextureMeta.TexId => TextureMeta.TexInf,
        else => @compileError("InfOfId: unsupported type"),
    };
}

pub fn IdOfRes(comptime T: type) type {
    return switch (T) {
        Buffer => BufferMeta.BufId,
        Texture => TextureMeta.TexId,
        else => @compileError("IdOfRes: unsupported type"),
    };
}

pub fn InfOfRes(comptime T: type) type {
    return switch (T) {
        Buffer => BufferMeta.BufInf,
        Texture => TextureMeta.TexInf,
        else => @compileError("InfOfRes: unsupported type"),
    };
}

pub fn ResOfInf(comptime T: type) type {
    return switch (T) {
        BufferMeta.BufInf => Buffer,
        TextureMeta.TexInf => Texture,
        else => @compileError("ResOfInf: unsupported type"),
    };
}

pub fn ResOfId(comptime T: type) type {
    return switch (T) {
        BufferMeta.BufId => Buffer,
        TextureMeta.TexId => Texture,
        else => @compileError("ResOfId: unsupported type"),
    };
}

pub fn MetaOfRes(comptime T: type) type {
    return switch (T) {
        Buffer => BufferMeta,
        Texture => TextureMeta,
        else => @compileError("MetaOfRes: unsupported type"),
    };
}

pub fn MetaOfId(comptime T: type) type {
    return switch (T) {
        BufferMeta.BufId => BufferMeta,
        TextureMeta.TexId => TextureMeta,
        else => @compileError("MetaOfId: unsupported type"),
    };
}

pub fn typeName(comptime T: type) []const u8 {
    const name = @typeName(T);
    return if (std.mem.lastIndexOfScalar(u8, name, '.')) |i| name[i + 1 ..] else name;
}
