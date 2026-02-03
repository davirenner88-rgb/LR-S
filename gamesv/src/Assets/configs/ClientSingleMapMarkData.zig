basicData: MapMarkBasicData,

pub const MapMarkBasicData = struct {
    templateId: []const u8,
    markInstId: []const u8,
    pos: struct {
        x: f32,
        y: f32,
        z: f32,
    },
};
