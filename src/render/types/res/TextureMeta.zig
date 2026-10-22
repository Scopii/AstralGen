const TexId = @import("../../../.configs/idConfig.zig").TexId;
const rc = @import("../../../.configs/renderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");
const std = @import("std");

pub const TextureMeta = struct {
    typ: vhE.TexTyp,
    texUse: vhE.TexUsage,
    descriptors: vhE.TexDescriptorUsage,
    update: vhE.UpdateType,
    resize: vhE.ResizeType,
    mem: vhE.MemUsage,
    updateSlot: u8 = rc.MAX_IN_FLIGHT - 1,
    lastUpdateFrame: u64 = std.math.maxInt(u64),
    viewType: vk.VkImageViewType,

    pub const TexDesc = struct {
        share: enum { persistent, transient },
        mem: vhE.MemUsage,
        typ: vhE.TexTyp,
        texUse: vhE.TexUsage,
        descriptors: vhE.TexDescriptorUsage,
        width: u32,
        height: u32,
        depth: u32 = 1,
        update: vhE.UpdateType,
        resize: vhE.ResizeType = .Block,
        fitPass: bool,

        pub fn makeTransient(mem: vhE.MemUsage, typ: vhE.TexTyp, width: u32, height: u32, depth: u32) TexDesc {
            return .{
                .share = .transient,
                .mem = mem,
                .typ = typ,
                .texUse = .{},
                .descriptors = .None,
                .width = width,
                .height = height,
                .depth = depth,
                .update = .Rarely,
                .resize = .Block,
                .fitPass = true,
            };
        }

        pub fn makePersistent(mem: vhE.MemUsage, typ: vhE.TexTyp, width: u32, height: u32, depth: u32, texUse: vhE.TexUsage) TexDesc {
            var descriptors: vhE.TexDescriptorUsage = .None;

            const needsSampled: bool = texUse.sampled or texUse.colorAtt or texUse.depthAtt;
            const needsStorage: bool = texUse.storage;

            if (needsSampled == true and needsStorage == true) descriptors = .StorageSampled;
            if (needsSampled == false and needsStorage == true) descriptors = .StorageOnly;
            if (needsSampled == true and needsStorage == false) descriptors = .SampledOnly;

            return .{
                .share = .persistent,
                .mem = mem,
                .typ = typ,
                .texUse = texUse,
                .descriptors = descriptors,
                .width = width,
                .height = height,
                .depth = depth,
                .update = .Rarely,
                .resize = .Fit,
                .fitPass = false,
            };
        }

        pub fn guessMemoryCost(self: *const TexDesc) u64 {
            const bytesPerPixel = self.typ.bytesPerPixel();
            const rawMemory = @as(u64, self.width) * @as(u64, self.height) * @as(u64, self.depth) * bytesPerPixel;

            return switch (self.update) {
                .Rarely => rawMemory,
                .Often, .PerFrame => rawMemory * rc.MAX_IN_FLIGHT,

                // .Rarely, .Often, .PerFrame => rawMemory,
            };
        }
    };

    pub const TexInf = struct {
        id: TexId,
        mem: vhE.MemUsage,
        typ: vhE.TexTyp,
        texUse: vhE.TexUsage,
        descriptors: vhE.TexDescriptorUsage,
        width: u32,
        height: u32,
        depth: u32 = 1,
        update: vhE.UpdateType,
        resize: vhE.ResizeType = .Block,
    };

    pub fn create(texInf: TexInf) TexInf {
        return texInf;
    }
};
