const std = @import("std");
const logic = @import("../../logic.zig");

pub const NetID = enum(u64) {
    none = 0,
    _,
};

pub const Handle = enum(u32) {
    _,
};

net_id: NetID,
template_id: i32,
position: Vector,
rotation: Vector,
hp: f64,
extra: Extra,

pub const Extra = union(enum) {
    character: Character,
};

pub const Vector = struct {
    pub const zero: Vector = .{ .x = 0, .y = 0, .z = 0 };

    x: f32,
    y: f32,
    z: f32,
};

pub const Character = struct {
    level: i32,
    char_index: logic.Player.CharBag.CharIndex,
    // TODO: attrs, battle_mgr_info representation.
};
