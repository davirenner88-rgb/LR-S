const std = @import("std");
const pb = @import("proto").pb;
const logic = @import("../../logic.zig");
const Session = @import("../../Session.zig");
const Assets = @import("../../Assets.zig");

const Level = logic.Level;
const Player = logic.Player;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub fn enterSceneOnLogin(
    rx: logic.event.Receiver(.login),
    tx: logic.event.Sender(.change_scene_begin),
) !void {
    _ = rx;

    try tx.send(.{});
}

fn respawnCharTeam(
    gpa: Allocator,
    char_bag: *const Player.CharBag,
    cur_scene: *const Player.Scene.Current,
    level: *Level,
) Level.SpawnError!void {
    // Despawn previous team
    var team = level.team();
    var char_net_id = team.next();
    while (char_net_id != .none) : (char_net_id = team.next()) {
        const handle = level.getObjectByNetId(char_net_id).?;
        level.despawn(handle);
    }

    // Spawn new team
    const position: Level.Object.Vector = .{
        .x = cur_scene.position[0],
        .y = cur_scene.position[1],
        .z = cur_scene.position[2],
    };

    const rotation: Level.Object.Vector = .{
        .x = cur_scene.rotation[0],
        .y = cur_scene.rotation[1],
        .z = cur_scene.rotation[2],
    };

    const team_index = char_bag.meta.curr_team_index;
    const chars = char_bag.chars.slice();

    for (char_bag.teams.items(.char_team)[team_index]) |slot| {
        const char_index = slot.charIndex() orelse continue;
        const i = @intFromEnum(char_index);

        const char_template_id_num = chars.items(.template_id)[i];

        _ = try level.spawn(
            gpa,
            .{
                .template_id = char_template_id_num,
                .position = position,
                .rotation = rotation,
                .hp = chars.items(.hp)[i],
            },
            .{ .character = .{
                .level = chars.items(.level)[i],
                .char_index = char_index,
            } },
        );
    }
}

pub fn beginChangingScene(
    rx: logic.event.Receiver(.change_scene_begin),
    gpa: logic.Resource.Allocator(.gpa),
    session: *Session,
    base: Player.Component(.base),
    scene: Player.Component(.scene),
    char_bag: Player.Component(.char_bag),
    level: *Level,
) !void {
    _ = rx;

    level.reset();
    try respawnCharTeam(gpa.interface, char_bag.data, &scene.data.current, level);

    const position: pb.VECTOR = .{
        .X = scene.data.current.position[0],
        .Y = scene.data.current.position[1],
        .Z = scene.data.current.position[2],
    };

    try session.send(pb.SC_CHANGE_SCENE_BEGIN_NOTIFY{
        .scene_num_id = scene.data.current.level_id,
        .position = position,
        .pass_through_data = .init,
    });

    try session.send(pb.SC_ENTER_SCENE_NOTIFY{
        .role_id = base.data.role_id,
        .scene_num_id = scene.data.current.level_id,
        .position = position,
        .pass_through_data = .init,
    });
}

pub fn refreshCharTeam(
    rx: logic.event.Receiver(.char_bag_team_modified),
    gpa: logic.Resource.Allocator(.gpa),
    char_bag: Player.Component(.char_bag),
    scene: Player.Component(.scene),
    level: *Level,
    sync_tx: logic.event.Sender(.sync_self_scene),
) !void {
    switch (rx.payload.modification) {
        .set_leader => return, // Doesn't require any action from server.
        .set_char_team => if (rx.payload.team_index == char_bag.data.meta.curr_team_index) {
            // If the current active team has been modified, it has to be re-spawned.
            try respawnCharTeam(gpa.interface, char_bag.data, &scene.data.current, level);
            try sync_tx.send(.{ .reason = .team_modified });
        },
    }
}

pub fn syncSelfScene(
    rx: logic.event.Receiver(.sync_self_scene),
    session: *Session,
    arena: logic.Resource.Allocator(.arena),
    char_bag: Player.Component(.char_bag),
    scene: Player.Component(.scene),
    level: *Level,
    assets: *const Assets,
) !void {
    const reason: pb.SELF_INFO_REASON_TYPE = switch (rx.payload.reason) {
        .entrance => .SLR_ENTER_SCENE,
        .team_modified => .SLR_CHANGE_TEAM,
    };

    const team_index = char_bag.data.meta.curr_team_index;
    const leader_index = char_bag.data.teams.items(.leader_index)[team_index];

    var self_scene_info: pb.SC_SELF_SCENE_INFO = .{
        .scene_num_id = scene.data.current.level_id,
        .self_info_reason = @intFromEnum(reason),
        .teamInfo = .{
            .team_type = .CHAR_BAG_TEAM_TYPE_MAIN,
            .team_index = @intCast(team_index),
            .cur_leader_id = leader_index.objectId(),
            .team_change_token = 0,
        },
        .scene_impl = .{ .empty = .{} },
        .detail = .{},
    };

    const objects = level.objects.slice();
    for (0..objects.len) |i| {
        const position = objects.items(.position)[i];
        const rotation = objects.items(.rotation)[i];
        const net_id = @intFromEnum(objects.items(.net_id)[i]);

        var common_info: pb.SCENE_OBJECT_COMMON_INFO = .{
            .id = net_id,
            .position = .{ .X = position.x, .Y = position.y, .Z = position.z },
            .rotation = .{ .X = rotation.x, .Y = rotation.y, .Z = rotation.z },
            .scene_num_id = scene.data.current.level_id,
            .hp = objects.items(.hp)[i],
        };

        switch (objects.items(.extra)[i]) {
            .character => |extra| {
                const template_id_num = objects.items(.template_id)[i];
                const template_id = assets.numToStr(.char_id, template_id_num).?;

                common_info.type = 0;
                common_info.templateid = template_id;

                var scene_char: pb.SCENE_CHARACTER = .{
                    .level = extra.level,
                    .common_info = common_info,
                    .battle_info = .{
                        .msg_generation = @intCast(net_id),
                        .battle_inst_id = @intCast(net_id),
                        .part_inst_info = .init,
                        .skill_list = try packCharacterSkills(arena.interface, assets, template_id),
                    },
                };

                const char_data = assets.table(.character).getPtr(template_id).?;
                for (char_data.attributes[0].Attribute.attrs) |attr| {
                    try scene_char.attrs.append(arena.interface, .{
                        .attr_type = @intFromEnum(attr.attrType),
                        .basic_value = attr.attrValue,
                        .value = attr.attrValue,
                    });
                }

                try self_scene_info.detail.?.char_list.append(arena.interface, scene_char);
            },
        }
    }

    try session.send(self_scene_info);
}

pub fn refreshVisibleObjects(
    rx: logic.event.Receiver(.refresh_visible_objects),
    session: *Session,
    arena: logic.Resource.Allocator(.arena),
    scene: Player.Component(.scene),
    assets: *const Assets,
) !void {
    const objects_per_message: usize = 128; // TODO(Session): message fragmentation.

    _ = rx;

    const level_id = scene.data.current.level_id;
    var container: pb.SCENE_OBJECT_DETAIL_CONTAINER = .init;

    const brief_map = &assets.world_entity_registry.worldEntityBriefInfos;
    for (brief_map.map.keys(), brief_map.map.values()) |id, info| {
        if (@divFloor(id, 100_000_000) != level_id)
            continue;

        if (info.objectType() != .enemy) continue;
        const template_id = info.detailId orelse continue;

        const enemy_attrs = assets.table(.enemy_attribute_template).getPtr(template_id) orelse continue;
        const common_info: pb.SCENE_OBJECT_COMMON_INFO = .{
            .id = id,
            .type = 3,
            .templateid = template_id,
            .position = .{ .X = info.position.x, .Y = info.position.y, .Z = info.position.z },
            .rotation = .{ .X = info.rotation.x, .Y = info.rotation.y, .Z = info.rotation.z },
            .scene_num_id = level_id,
            .hp = 100,
        };

        var monster: pb.SCENE_MONSTER = .{
            .common_info = common_info,
            .level = 1,
            .battle_info = .{
                .msg_generation = @truncate(id),
                .battle_inst_id = @truncate(id),
                .part_inst_info = .init,
            },
        };

        for (enemy_attrs.levelDependentAttributes[0].attrs) |attr| {
            try monster.attrs.append(arena.interface, .{
                .attr_type = @intFromEnum(attr.attrType),
                .basic_value = attr.attrValue,
                .value = attr.attrValue,
            });
        }

        for (enemy_attrs.levelIndependentAttributes.attrs) |attr| {
            try monster.attrs.append(arena.interface, .{
                .attr_type = @intFromEnum(attr.attrType),
                .basic_value = attr.attrValue,
                .value = attr.attrValue,
            });
        }

        try container.monster_list.append(arena.interface, monster);

        if (container.monster_list.items.len == objects_per_message) {
            try session.send(pb.SC_OBJECT_ENTER_VIEW{
                .detail = container,
            });

            container = .init;
        }
    }

    if (container.monster_list.items.len != 0) {
        try session.send(pb.SC_OBJECT_ENTER_VIEW{
            .detail = container,
        });
    }
}

fn packCharacterSkills(
    arena: Allocator,
    assets: *const Assets,
    template_id: []const u8,
) Allocator.Error!ArrayList(pb.SERVER_SKILL) {
    const char_skills = assets.char_skill_map.map.getPtr(template_id).?.all_skills;
    var list: ArrayList(pb.SERVER_SKILL) = try .initCapacity(
        arena,
        char_skills.len + assets.common_skill_config.config.Character.skillConfigs.len,
    );

    errdefer comptime unreachable;

    for (char_skills, 1..) |name, i| {
        list.appendAssumeCapacity(.{
            .skill_id = .{
                .id_impl = .{ .str_id = name },
                .type = .BATTLE_ACTION_OWNER_TYPE_SKILL,
            },
            .blackboard = .{},
            .inst_id = (100 + i),
            .level = 1,
            .source = .BATTLE_SKILL_SOURCE_DEFAULT,
            .potential_lv = 1,
            .is_enable = true,
        });
    }

    for (assets.common_skill_config.config.Character.skillConfigs, char_skills.len + 1..) |config, i| {
        list.appendAssumeCapacity(.{
            .skill_id = .{
                .id_impl = .{ .str_id = config.skillId },
                .type = .BATTLE_ACTION_OWNER_TYPE_SKILL,
            },
            .blackboard = .{},
            .inst_id = (100 + i),
            .level = 1,
            .source = .BATTLE_SKILL_SOURCE_DEFAULT,
            .potential_lv = 1,
            .is_enable = true,
        });
    }

    return list;
}
