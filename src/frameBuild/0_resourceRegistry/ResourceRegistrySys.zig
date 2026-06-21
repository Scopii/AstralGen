const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const ResourceRegistryData = @import("ResourceRegistryData.zig").ResourceRegistryData;
const PassDef = @import("../../render/types/pass/PassDef.zig").PassDef;
const ShaderInf = @import("../../shader/ShaderInf.zig").ShaderInf;
const std = @import("std");

pub const BufDescId = packed struct { val: u16 };
pub const TexDescId = packed struct { val: u16 };
pub const PassDefId = packed struct { val: u16 };

pub const BufInstanceId = packed struct { val: u16 };
pub const TexInstanceId = packed struct { val: u16 };
pub const PassInstanceId = packed struct { val: u16 };

pub const ResourceRegistrySys = struct {};
