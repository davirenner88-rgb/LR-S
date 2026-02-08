const std = @import("std");
const json = std.json;

pub const CommonSkillConfig = @import("configs/CommonSkillConfig.zig");
pub const LevelConfig = @import("configs/LevelConfig.zig");
pub const ClientSingleMapMarkData = @import("configs/ClientSingleMapMarkData.zig");
pub const TeleportValidationDataTable = @import("configs/TeleportValidationDataTable.zig");
pub const WorldEntityRegistry = @import("configs/WorldEntityRegistry.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn loadJsonConfig(
    comptime T: type,
    io: Io,
    arena: Allocator,
    filename: []const u8,
) !T {
    const config_dir = try Io.Dir.cwd().openDir(io, "assets/configs/", .{});
    defer config_dir.close(io);

    const file = try config_dir.openFile(io, filename, .{});
    defer file.close(io);

    var buffer: [16384]u8 = undefined;
    var file_reader = file.reader(io, &buffer);

    var json_reader: json.Reader = .init(arena, &file_reader.interface);
    defer json_reader.deinit();

    return try json.parseFromTokenSourceLeaky(
        T,
        arena,
        &json_reader,
        .{ .ignore_unknown_fields = true },
    );
}

// std.json.ArrayHashMap, modified to work with integer keys.
pub fn ArrayIntMap(comptime Int: type, comptime T: type) type {
    return struct {
        map: std.AutoArrayHashMapUnmanaged(Int, T) = .empty,

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            self.map.deinit(allocator);
        }

        pub fn jsonParse(allocator: Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            var map: std.AutoArrayHashMapUnmanaged(Int, T) = .empty;
            errdefer map.deinit(allocator);

            if (.object_begin != try source.next()) return error.UnexpectedToken;
            while (true) {
                const token = try source.nextAlloc(allocator, options.allocate.?);
                switch (token) {
                    inline .string, .allocated_string => |k| {
                        const int = std.fmt.parseInt(Int, k, 10) catch return error.UnexpectedToken;
                        const gop = try map.getOrPut(allocator, int);
                        if (gop.found_existing) {
                            switch (options.duplicate_field_behavior) {
                                .use_first => {
                                    // Parse and ignore the redundant value.
                                    // We don't want to skip the value, because we want type checking.
                                    _ = try std.json.innerParse(T, allocator, source, options);
                                    continue;
                                },
                                .@"error" => return error.DuplicateField,
                                .use_last => {},
                            }
                        }
                        gop.value_ptr.* = try std.json.innerParse(T, allocator, source, options);
                    },
                    .object_end => break,
                    else => unreachable,
                }
            }
            return .{ .map = map };
        }
    };
}
