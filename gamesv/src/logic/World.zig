// Describes player-local state of the world.
const World = @This();
const std = @import("std");
const mem = @import("common").mem;
const logic = @import("../logic.zig");
const Session = @import("../Session.zig");
const Assets = @import("../Assets.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const PlayerId = struct {
    pub const max_length: usize = 16;

    uid: mem.LimitedString(max_length),
};

// TODO: this can be made a persistent Player component.
pub const Location = struct {
    const default_level = "map02_lv001";

    level: i32,
    position: [3]f32,

    fn createDefault(assets: *const Assets) Location {
        const level_config = assets.level_config_table.getPtr(default_level).?;

        return .{
            .level = level_config.idNum,
            .position = .{
                level_config.playerInitPos.x,
                level_config.playerInitPos.y,
                level_config.playerInitPos.z,
            },
        };
    }
};

player_id: PlayerId,
session: *Session, // TODO: should it be here this way? Do we need an abstraction?
res: logic.Resource,
player: logic.Player,
location: Location,

pub fn init(
    session: *Session,
    assets: *const Assets,
    uid: mem.LimitedString(PlayerId.max_length),
    player: logic.Player,
    gpa: Allocator,
    io: Io,
) World {
    _ = gpa;
    return .{
        .player_id = .{ .uid = uid },
        .session = session,
        .player = player,
        .res = .init(assets, io),
        .location = .createDefault(assets),
    };
}

pub fn deinit(world: *World, gpa: Allocator) void {
    world.player.deinit(gpa);
}

pub const GetComponentError = error{
    ComponentUnavailable,
};

pub fn getComponentByType(world: *World, comptime T: type) GetComponentError!T {
    switch (T) {
        PlayerId => return world.player_id,
        *Location, *const Location => return &world.location,
        *Session => return world.session,
        *logic.Resource.PingTimer => return &world.res.ping_timer,
        *const Assets => return world.res.assets,
        Io => return world.res.io(),
        else => {
            if (comptime logic.Player.isComponent(T)) {
                return world.player.getComponentByType(T);
            }

            @compileError("World.getComponentByType(" ++ @typeName(T) ++ ") is unsupported");
        },
    }
}
