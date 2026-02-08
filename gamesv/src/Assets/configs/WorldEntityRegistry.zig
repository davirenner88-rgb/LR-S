const std = @import("std");
const logic = @import("../../logic.zig");
const configs = @import("../configs.zig");

worldEntityBriefInfos: configs.ArrayIntMap(u64, WorldEntityBriefInfo),

pub const WorldEntityBriefInfo = struct {
    entityType: u32,
    detailId: ?[]const u8,
    position: logic.Level.Object.Vector,
    rotation: logic.Level.Object.Vector,
};
