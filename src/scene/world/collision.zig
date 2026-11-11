const std = @import("std");
const math = @import("../../math.zig");
const Vec3 = math.Vec3;

// Limiar da componente Y da normal para classificar triângulos (estilo SM64)
pub const FLOOR_NORMAL_MIN_Y: f32 = 0.5;
pub const CEILING_NORMAL_MAX_Y: f32 = -0.5;
pub const COLLISION_CELL_SIZE: f32 = 4.0;
pub const MAX_CELLS_PER_TRIANGLE: i64 = 64;

pub const CellKey = struct {
    x: i32,
    z: i32,
};

// 🔺 Triângulo estático em espaço de mundo com normal pré-calculada
pub const CollisionTriangle = struct {
    a: Vec3,
    b: Vec3,
    c: Vec3,
    normal: Vec3,
};

pub const FloorHit = struct {
    y: f32,
    normal: Vec3,
};

fn cellCoord(value: f32) i32 {
    return @intFromFloat(@floor(value / COLLISION_CELL_SIZE));
}

/// Índice uniforme XZ: cada célula contém índices nas listas estáticas de triângulos.
/// Triângulos enormes ficam em `large_triangles` para não preencherem muitas células.
pub const TriangleGrid = struct {
    cells: std.AutoHashMapUnmanaged(CellKey, std.ArrayListUnmanaged(usize)) = .empty,
    large_triangles: std.ArrayListUnmanaged(usize) = .empty,
    min_cells: std.ArrayListUnmanaged(CellKey) = .empty,

    pub fn deinit(self: *TriangleGrid, allocator: std.mem.Allocator) void {
        var it = self.cells.valueIterator();
        while (it.next()) |list| {
            list.deinit(allocator);
        }
        self.cells.deinit(allocator);
        self.large_triangles.deinit(allocator);
        self.min_cells.deinit(allocator);
        self.* = .{};
    }

    pub fn build(allocator: std.mem.Allocator, triangles: []const CollisionTriangle) !TriangleGrid {
        var grid = TriangleGrid{};
        errdefer grid.deinit(allocator);

        try grid.min_cells.ensureTotalCapacity(allocator, triangles.len);

        for (triangles, 0..) |tri, index| {
            const min_x = @min(tri.a.x, @min(tri.b.x, tri.c.x));
            const max_x = @max(tri.a.x, @max(tri.b.x, tri.c.x));
            const min_z = @min(tri.a.z, @min(tri.b.z, tri.c.z));
            const max_z = @max(tri.a.z, @max(tri.b.z, tri.c.z));

            const min_cell_x = cellCoord(min_x);
            const max_cell_x = cellCoord(max_x);
            const min_cell_z = cellCoord(min_z);
            const max_cell_z = cellCoord(max_z);

            grid.min_cells.appendAssumeCapacity(.{ .x = min_cell_x, .z = min_cell_z });

            const cell_count = (@as(i64, max_cell_x) - @as(i64, min_cell_x) + 1) *
                (@as(i64, max_cell_z) - @as(i64, min_cell_z) + 1);

            if (cell_count > MAX_CELLS_PER_TRIANGLE) {
                try grid.large_triangles.append(allocator, index);
                continue;
            }

            var cell_x = min_cell_x;
            while (cell_x <= max_cell_x) : (cell_x += 1) {
                var cell_z = min_cell_z;
                while (cell_z <= max_cell_z) : (cell_z += 1) {
                    const gop = try grid.cells.getOrPut(allocator, .{ .x = cell_x, .z = cell_z });
                    if (!gop.found_existing) {
                        gop.value_ptr.* = .empty;
                    }
                    try gop.value_ptr.append(allocator, index);
                }
            }
        }

        return grid;
    }

    pub fn forPoint(
        self: *const TriangleGrid,
        x: f32,
        z: f32,
        context: anytype,
        comptime visit: fn (@TypeOf(context), usize) void,
    ) void {
        const key = CellKey{ .x = cellCoord(x), .z = cellCoord(z) };
        if (self.cells.get(key)) |indices| {
            for (indices.items) |index| {
                visit(context, index);
            }
        }
        for (self.large_triangles.items) |index| {
            visit(context, index);
        }
    }

    pub fn forAabb(
        self: *const TriangleGrid,
        min_x: f32,
        max_x: f32,
        min_z: f32,
        max_z: f32,
        context: anytype,
        comptime visit: fn (@TypeOf(context), usize) void,
    ) void {
        const min_cell_x = cellCoord(min_x);
        const max_cell_x = cellCoord(max_x);
        const min_cell_z = cellCoord(min_z);
        const max_cell_z = cellCoord(max_z);

        var cell_x = min_cell_x;
        while (cell_x <= max_cell_x) : (cell_x += 1) {
            var cell_z = min_cell_z;
            while (cell_z <= max_cell_z) : (cell_z += 1) {
                const key = CellKey{ .x = cell_x, .z = cell_z };
                if (self.cells.get(key)) |indices| {
                    for (indices.items) |index| {
                        const triangle_min = self.min_cells.items[index];
                        const first_overlap_x = @max(min_cell_x, triangle_min.x);
                        const first_overlap_z = @max(min_cell_z, triangle_min.z);
                        // Triângulos que aparecem em várias células consultadas são
                        // processados apenas na primeira célula de interseção.
                        if (cell_x == first_overlap_x and cell_z == first_overlap_z) {
                            visit(context, index);
                        }
                    }
                }
            }
        }
        for (self.large_triangles.items) |index| {
            visit(context, index);
        }
    }
};

// 🗺️ Dados de colisão determinísticos do nível, divididos por classificação da normal
pub const LevelCollision = struct {
    allocator: std.mem.Allocator,
    floors: std.ArrayListUnmanaged(CollisionTriangle) = .empty,
    walls: std.ArrayListUnmanaged(CollisionTriangle) = .empty,
    ceilings: std.ArrayListUnmanaged(CollisionTriangle) = .empty,
    floor_grid: TriangleGrid = .{},
    wall_grid: TriangleGrid = .{},
    ceiling_grid: TriangleGrid = .{},
    ready: bool = false,

    pub fn init(allocator: std.mem.Allocator) LevelCollision {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LevelCollision) void {
        self.clear();
        self.floors.deinit(self.allocator);
        self.walls.deinit(self.allocator);
        self.ceilings.deinit(self.allocator);
    }

    pub fn clear(self: *LevelCollision) void {
        self.floors.clearRetainingCapacity();
        self.walls.clearRetainingCapacity();
        self.ceilings.clearRetainingCapacity();
        self.floor_grid.deinit(self.allocator);
        self.wall_grid.deinit(self.allocator);
        self.ceiling_grid.deinit(self.allocator);
        self.ready = false;
    }

    pub fn addTriangle(self: *LevelCollision, a: Vec3, b: Vec3, c: Vec3) !void {
        const normal = b.sub(a).cross(c.sub(a)).normalizeOrZero();
        if (normal.eql(Vec3.ZERO)) return;

        const t = CollisionTriangle{ .a = a, .b = b, .c = c, .normal = normal };
        if (normal.y > FLOOR_NORMAL_MIN_Y) {
            try self.floors.append(self.allocator, t);
        } else if (normal.y < CEILING_NORMAL_MAX_Y) {
            try self.ceilings.append(self.allocator, t);
        } else {
            try self.walls.append(self.allocator, t);
        }
    }

    pub fn rebuildIndices(self: *LevelCollision) !void {
        self.floor_grid.deinit(self.allocator);
        self.wall_grid.deinit(self.allocator);
        self.ceiling_grid.deinit(self.allocator);

        self.floor_grid = try TriangleGrid.build(self.allocator, self.floors.items);
        self.wall_grid = try TriangleGrid.build(self.allocator, self.walls.items);
        self.ceiling_grid = try TriangleGrid.build(self.allocator, self.ceilings.items);

        self.ready = !(self.floors.items.len == 0 and self.walls.items.len == 0 and self.ceilings.items.len == 0);
        std.log.info(
            "Colisão do nível: {d} pisos, {d} paredes, {d} tetos",
            .{ self.floors.items.len, self.walls.items.len, self.ceilings.items.len },
        );
    }

    // Altura do piso mais alto sob (x, z) cujo Y seja <= max_y. Retorna (altura, normal).
    pub fn findFloor(self: *const LevelCollision, x: f32, z: f32, max_y: f32) ?FloorHit {
        const Ctx = struct {
            floors: []const CollisionTriangle,
            x: f32,
            z: f32,
            max_y: f32,
            best: ?FloorHit = null,

            fn visit(ctx: *@This(), index: usize) void {
                const tri = &ctx.floors[index];
                if (heightOnTriangle(tri, ctx.x, ctx.z)) |y| {
                    if (y <= ctx.max_y) {
                        if (ctx.best == null or y > ctx.best.?.y) {
                            ctx.best = .{ .y = y, .normal = tri.normal };
                        }
                    }
                }
            }
        };

        var ctx = Ctx{
            .floors = self.floors.items,
            .x = x,
            .z = z,
            .max_y = max_y,
        };
        self.floor_grid.forPoint(x, z, &ctx, Ctx.visit);
        return ctx.best;
    }

    // Altura do teto mais baixo sobre (x, z) cujo Y seja >= min_y.
    pub fn findCeiling(self: *const LevelCollision, x: f32, z: f32, min_y: f32) ?f32 {
        const Ctx = struct {
            ceilings: []const CollisionTriangle,
            x: f32,
            z: f32,
            min_y: f32,
            best: ?f32 = null,

            fn visit(ctx: *@This(), index: usize) void {
                const tri = &ctx.ceilings[index];
                if (heightOnTriangle(tri, ctx.x, ctx.z)) |y| {
                    if (y >= ctx.min_y) {
                        if (ctx.best == null or y < ctx.best.?) {
                            ctx.best = y;
                        }
                    }
                }
            }
        };

        var ctx = Ctx{
            .ceilings = self.ceilings.items,
            .x = x,
            .z = z,
            .min_y = min_y,
        };
        self.ceiling_grid.forPoint(x, z, &ctx, Ctx.visit);
        return ctx.best;
    }

    // Empurra um ponto/esfera para fora das paredes. Retorna a normal acumulada dos empurrões.
    pub fn pushOutOfWalls(self: *const LevelCollision, pos: *Vec3, radius: f32) Vec3 {
        const Ctx = struct {
            walls: []const CollisionTriangle,
            pos: *Vec3,
            radius: f32,
            pushed: Vec3 = Vec3.ZERO,

            fn visit(ctx: *@This(), index: usize) void {
                const tri = &ctx.walls[index];
                const min_tx = @min(tri.a.x, @min(tri.b.x, tri.c.x));
                const max_tx = @max(tri.a.x, @max(tri.b.x, tri.c.x));
                const min_tz = @min(tri.a.z, @min(tri.b.z, tri.c.z));
                const max_tz = @max(tri.a.z, @max(tri.b.z, tri.c.z));

                // Barreira barata antes do cálculo de ponto mais próximo no triângulo.
                if (ctx.pos.x + ctx.radius < min_tx or
                    ctx.pos.x - ctx.radius > max_tx or
                    ctx.pos.z + ctx.radius < min_tz or
                    ctx.pos.z - ctx.radius > max_tz)
                {
                    return;
                }

                const closest = closestPointOnTriangle(ctx.pos.*, tri.a, tri.b, tri.c);
                const delta = ctx.pos.sub(closest);
                const dist = delta.length();
                if (dist < ctx.radius) {
                    var dir = if (dist > 1e-5) delta.scale(1.0 / dist) else tri.normal;
                    dir.y = 0.0;
                    dir = dir.normalizeOrZero();
                    if (!dir.eql(Vec3.ZERO)) {
                        ctx.pos.* = ctx.pos.add(dir.scale(ctx.radius - dist));
                        ctx.pushed = ctx.pushed.add(dir);
                    }
                }
            }
        };

        var ctx = Ctx{
            .walls = self.walls.items,
            .pos = pos,
            .radius = radius,
        };
        self.wall_grid.forAabb(
            pos.x - radius,
            pos.x + radius,
            pos.z - radius,
            pos.z + radius,
            &ctx,
            Ctx.visit,
        );
        return ctx.pushed;
    }
};

// Altura Y do plano do triângulo no ponto (x, z), se (x, z) estiver dentro da projeção XZ
pub fn heightOnTriangle(tri: *const CollisionTriangle, x: f32, z: f32) ?f32 {
    const a = tri.a;
    const b = tri.b;
    const c = tri.c;
    const d = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z);
    if (@abs(d) < 1e-8) {
        return null;
    }
    const l1 = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d;
    const l2 = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d;
    const l3 = 1.0 - l1 - l2;
    const eps: f32 = -1e-4;
    if (l1 < eps or l2 < eps or l3 < eps) {
        return null;
    }
    return l1 * a.y + l2 * b.y + l3 * c.y;
}

// Ponto mais próximo em um triângulo (Ericson, Real-Time Collision Detection)
pub fn closestPointOnTriangle(p: Vec3, a: Vec3, b: Vec3, c: Vec3) Vec3 {
    const ab = b.sub(a);
    const ac = c.sub(a);
    const ap = p.sub(a);
    const d1 = ab.dot(ap);
    const d2 = ac.dot(ap);
    if (d1 <= 0.0 and d2 <= 0.0) {
        return a;
    }

    const bp = p.sub(b);
    const d3 = ab.dot(bp);
    const d4 = ac.dot(bp);
    if (d3 >= 0.0 and d4 <= d3) {
        return b;
    }

    const vc = d1 * d4 - d3 * d2;
    if (vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0) {
        return a.add(ab.scale(d1 / (d1 - d3)));
    }

    const cp = p.sub(c);
    const d5 = ab.dot(cp);
    const d6 = ac.dot(cp);
    if (d6 >= 0.0 and d5 <= d6) {
        return c;
    }

    const vb = d5 * d2 - d1 * d6;
    if (vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0) {
        return a.add(ac.scale(d2 / (d2 - d6)));
    }

    const va = d3 * d6 - d5 * d4;
    if (va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0) {
        return b.add(c.sub(b).scale((d4 - d3) / ((d4 - d3) + (d5 - d6))));
    }

    const denom = 1.0 / (va + vb + vc);
    return a.add(ab.scale(vb * denom)).add(ac.scale(vc * denom));
}

fn makeTestTriangle(a: Vec3, b: Vec3, c: Vec3) CollisionTriangle {
    return .{
        .a = a,
        .b = b,
        .c = c,
        .normal = Vec3.Y,
    };
}

test "point_grid_returns_triangles_covering_positive_and_negative_cells" {
    const allocator = std.testing.allocator;
    const triangles = [_]CollisionTriangle{
        makeTestTriangle(
            Vec3.new(-4.5, 0.0, -4.5),
            Vec3.new(-3.5, 0.0, -4.5),
            Vec3.new(-4.5, 0.0, -3.5),
        ),
        makeTestTriangle(
            Vec3.new(8.0, 0.0, 8.0),
            Vec3.new(9.0, 0.0, 8.0),
            Vec3.new(8.0, 0.0, 9.0),
        ),
    };

    var grid = try TriangleGrid.build(allocator, &triangles);
    defer grid.deinit(allocator);

    const Collector = struct {
        list: std.ArrayListUnmanaged(usize) = .empty,
        alloc: std.mem.Allocator,

        fn visit(self: *@This(), idx: usize) void {
            self.list.append(self.alloc, idx) catch unreachable;
        }
    };

    var col = Collector{ .alloc = allocator };
    defer col.list.deinit(allocator);

    grid.forPoint(-4.0, -4.0, &col, Collector.visit);
    try std.testing.expect(std.mem.indexOfScalar(usize, col.list.items, 0) != null);
    try std.testing.expect(std.mem.indexOfScalar(usize, col.list.items, 1) == null);

    col.list.clearRetainingCapacity();
    grid.forPoint(8.25, 8.25, &col, Collector.visit);
    try std.testing.expectEqualSlices(usize, &[_]usize{1}, col.list.items);
}

test "wall_aabb_query_visits_each_candidate_once_and_keeps_large_triangles" {
    const allocator = std.testing.allocator;
    const triangles = [_]CollisionTriangle{
        makeTestTriangle(
            Vec3.new(0.0, 0.0, 0.0),
            Vec3.new(9.0, 0.0, 0.0),
            Vec3.new(0.0, 0.0, 9.0),
        ),
        makeTestTriangle(
            Vec3.new(-100.0, 0.0, -100.0),
            Vec3.new(100.0, 0.0, -100.0),
            Vec3.new(0.0, 0.0, 100.0),
        ),
    };

    var grid = try TriangleGrid.build(allocator, &triangles);
    defer grid.deinit(allocator);

    try std.testing.expect(std.mem.indexOfScalar(usize, grid.large_triangles.items, 1) != null);

    const Collector = struct {
        list: std.ArrayListUnmanaged(usize) = .empty,
        alloc: std.mem.Allocator,

        fn visit(self: *@This(), idx: usize) void {
            self.list.append(self.alloc, idx) catch unreachable;
        }
    };

    var col = Collector{ .alloc = allocator };
    defer col.list.deinit(allocator);

    grid.forAabb(3.5, 4.5, 3.5, 4.5, &col, Collector.visit);
    std.mem.sort(usize, col.list.items, {}, std.sort.asc(usize));
    try std.testing.expectEqualSlices(usize, &[_]usize{ 0, 1 }, col.list.items);
}
