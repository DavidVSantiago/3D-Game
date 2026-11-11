const std = @import("std");

pub const c = @import("raylib_c");

const math = @import("math.zig");
const Vec3 = math.Vec3;
const Quat = math.Quat;

pub fn toRlVec3(v: Vec3) c.Vector3 {
    return .{ .x = v.x, .y = v.y, .z = v.z };
}

pub fn fromRlVec3(v: c.Vector3) Vec3 {
    return .{ .x = v.x, .y = v.y, .z = v.z };
}

pub fn quatToMatrix(q: Quat) c.Matrix {
    return c.QuaternionToMatrix(.{ .x = q.x, .y = q.y, .z = q.z, .w = q.w });
}

pub fn getEnv(name: [*:0]const u8) ?[]const u8 {
    const ptr = c.getenv(name) orelse return null;
    return std.mem.span(ptr);
}
