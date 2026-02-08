const std = @import("std");
const logic = @import("../../logic.zig");
const configs = @import("../configs.zig");

worldEntityBriefInfos: configs.ArrayIntMap(u64, WorldEntityBriefInfo),

pub const WorldEntityBriefInfo = struct {
    entityType: u32,
    detailId: ?[]const u8,
    position: logic.Level.Object.Vector,
    rotation: logic.Level.Object.Vector,

    pub fn objectType(info: WorldEntityBriefInfo) ObjectType {
        return std.enums.fromInt(ObjectType, info.entityType) orelse .invalid;
    }
};

pub const ObjectType = enum(u32) {
    all = 4294967295,
    invalid = 1,
    character = 8,
    enemy = 16,
    interactive = 32,
    projectile = 64,
    factory_region = 128,
    npc = 256,
    ability_entity = 512,
    cinematic_entity = 1024,
    remote_factory_entity = 2048,
    creature = 4096,
    god_entity = 8192,
    enemy_part = 16384,
    social_building = 32768,
    enemy_all = 16400,
};
