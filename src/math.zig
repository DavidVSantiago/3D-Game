const std = @import("std");

pub const Vec2 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub const ZERO = Vec2{ .x = 0.0, .y = 0.0 };

    pub fn new(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn eql(self: Vec2, other: Vec2) bool {
        return self.x == other.x and self.y == other.y;
    }
};

pub const Vec3 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub const ZERO = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    pub const ONE = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 };
    pub const X = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 };
    pub const Y = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    pub const Z = Vec3{ .x = 0.0, .y = 0.0, .z = 1.0 };

    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub fn scale(self: Vec3, s: f32) Vec3 {
        return .{
            .x = self.x * s,
            .y = self.y * s,
            .z = self.z * s,
        };
    }

    pub fn neg(self: Vec3) Vec3 {
        return .{ .x = -self.x, .y = -self.y, .z = -self.z };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn lengthSquared(self: Vec3) f32 {
        return self.dot(self);
    }

    pub fn length(self: Vec3) f32 {
        return @sqrt(self.lengthSquared());
    }

    pub fn normalize(self: Vec3) Vec3 {
        const len = self.length();
        if (len > 1e-8) {
            return self.scale(1.0 / len);
        }
        return ZERO;
    }

    pub fn normalizeOrZero(self: Vec3) Vec3 {
        const len = self.length();
        if (len > 1e-6 and std.math.isFinite(len)) {
            return self.scale(1.0 / len);
        }
        return ZERO;
    }

    pub fn lerp(self: Vec3, other: Vec3, t: f32) Vec3 {
        return .{
            .x = self.x + (other.x - self.x) * t,
            .y = self.y + (other.y - self.y) * t,
            .z = self.z + (other.z - self.z) * t,
        };
    }

    pub fn eql(self: Vec3, other: Vec3) bool {
        return self.x == other.x and self.y == other.y and self.z == other.z;
    }
};

pub const Quat = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 1.0,

    pub const IDENTITY = Quat{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 };

    pub fn fromAxisAngle(axis: Vec3, angle: f32) Quat {
        const len = axis.length();
        if (len < 1e-6) return IDENTITY;
        const n = axis.scale(1.0 / len);
        const half = angle * 0.5;
        const s = @sin(half);
        return .{
            .x = n.x * s,
            .y = n.y * s,
            .z = n.z * s,
            .w = @cos(half),
        };
    }

    pub fn fromRotationX(angle: f32) Quat {
        const half = angle * 0.5;
        return .{ .x = @sin(half), .y = 0.0, .z = 0.0, .w = @cos(half) };
    }

    pub fn fromRotationY(angle: f32) Quat {
        const half = angle * 0.5;
        return .{ .x = 0.0, .y = @sin(half), .z = 0.0, .w = @cos(half) };
    }

    pub fn fromRotationZ(angle: f32) Quat {
        const half = angle * 0.5;
        return .{ .x = 0.0, .y = 0.0, .z = @sin(half), .w = @cos(half) };
    }

    pub fn normalize(self: Quat) Quat {
        const len = @sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
        if (len < 1e-8) return IDENTITY;
        const inv = 1.0 / len;
        return .{
            .x = self.x * inv,
            .y = self.y * inv,
            .z = self.z * inv,
            .w = self.w * inv,
        };
    }

    pub fn mul(self: Quat, rhs: Quat) Quat {
        return .{
            .x = self.w * rhs.x + self.x * rhs.w + self.y * rhs.z - self.z * rhs.y,
            .y = self.w * rhs.y - self.x * rhs.z + self.y * rhs.w + self.z * rhs.x,
            .z = self.w * rhs.z + self.x * rhs.y - self.y * rhs.x + self.z * rhs.w,
            .w = self.w * rhs.w - self.x * rhs.x - self.y * rhs.y - self.z * rhs.z,
        };
    }

    pub fn mulVec3(self: Quat, v: Vec3) Vec3 {
        const u = Vec3.new(self.x, self.y, self.z);
        const s = self.w;
        return u.scale(2.0 * u.dot(v))
            .add(v.scale(s * s - u.dot(u)))
            .add(u.cross(v).scale(2.0 * s));
    }

    pub fn slerp(self: Quat, end_in: Quat, t: f32) Quat {
        var end = end_in;
        var cos_half_theta = self.x * end.x + self.y * end.y + self.z * end.z + self.w * end.w;

        if (cos_half_theta < 0.0) {
            end.x = -end.x;
            end.y = -end.y;
            end.z = -end.z;
            end.w = -end.w;
            cos_half_theta = -cos_half_theta;
        }

        if (cos_half_theta >= 0.9995) {
            const res = Quat{
                .x = self.x + t * (end.x - self.x),
                .y = self.y + t * (end.y - self.y),
                .z = self.z + t * (end.z - self.z),
                .w = self.w + t * (end.w - self.w),
            };
            return res.normalize();
        }

        const half_theta = std.math.acos(std.math.clamp(cos_half_theta, -1.0, 1.0));
        const sin_half_theta = @sqrt(1.0 - cos_half_theta * cos_half_theta);
        const ratio_a = @sin((1.0 - t) * half_theta) / sin_half_theta;
        const ratio_b = @sin(t * half_theta) / sin_half_theta;

        return .{
            .x = self.x * ratio_a + end.x * ratio_b,
            .y = self.y * ratio_a + end.y * ratio_b,
            .z = self.z * ratio_a + end.z * ratio_b,
            .w = self.w * ratio_a + end.w * ratio_b,
        };
    }

    pub fn toAxisAngle(self: Quat) struct { axis: Vec3, angle_rad: f32 } {
        const q = if (@abs(self.w) > 1.0) self.normalize() else self;
        const angle = 2.0 * std.math.acos(std.math.clamp(q.w, -1.0, 1.0));
        const den = @sqrt(@max(0.0, 1.0 - q.w * q.w));
        if (den > 1e-4) {
            return .{
                .axis = Vec3.new(q.x / den, q.y / den, q.z / den),
                .angle_rad = angle,
            };
        }
        return .{
            .axis = Vec3.X,
            .angle_rad = angle,
        };
    }
};
