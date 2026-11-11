use crate::scene::player::Player;
use crate::scene::world::terrain::{LevelRoot, TerrainMesh};
use bevy::prelude::*;
use bevy::render::mesh::{Indices, VertexAttributeValues};
use std::collections::HashMap;

// Limiar da componente Y da normal para classificar triângulos (estilo SM64)
const FLOOR_NORMAL_MIN_Y: f32 = 0.5;
const CEILING_NORMAL_MAX_Y: f32 = -0.5;
const COLLISION_CELL_SIZE: f32 = 4.0;
const MAX_CELLS_PER_TRIANGLE: i64 = 64;

// 🔺 Triângulo estático em espaço de mundo com normal pré-calculada
#[derive(Clone, Copy)]
pub struct CollisionTriangle {
    pub a: Vec3,
    pub b: Vec3,
    pub c: Vec3,
    pub normal: Vec3,
}

/// Índice uniforme XZ: cada célula contém índices nas listas estáticas de triângulos.
/// Triângulos enormes ficam em `large_triangles` para não preencherem muitas células.
#[derive(Default)]
struct TriangleGrid {
    cells: HashMap<(i32, i32), Vec<usize>>,
    large_triangles: Vec<usize>,
    min_cells: Vec<(i32, i32)>,
}

impl TriangleGrid {
    fn build(triangles: &[CollisionTriangle]) -> Self {
        let mut grid = Self::default();
        for (index, tri) in triangles.iter().enumerate() {
            let min_x = tri.a.x.min(tri.b.x).min(tri.c.x);
            let max_x = tri.a.x.max(tri.b.x).max(tri.c.x);
            let min_z = tri.a.z.min(tri.b.z).min(tri.c.z);
            let max_z = tri.a.z.max(tri.b.z).max(tri.c.z);
            let (min_cell_x, max_cell_x) = (cell_coord(min_x), cell_coord(max_x));
            let (min_cell_z, max_cell_z) = (cell_coord(min_z), cell_coord(max_z));
            grid.min_cells.push((min_cell_x, min_cell_z));
            let cell_count = (i64::from(max_cell_x) - i64::from(min_cell_x) + 1)
                * (i64::from(max_cell_z) - i64::from(min_cell_z) + 1);

            if cell_count > MAX_CELLS_PER_TRIANGLE {
                grid.large_triangles.push(index);
                continue;
            }

            for cell_x in min_cell_x..=max_cell_x {
                for cell_z in min_cell_z..=max_cell_z {
                    grid.cells.entry((cell_x, cell_z)).or_default().push(index);
                }
            }
        }
        grid
    }

    fn for_point(&self, x: f32, z: f32, mut visit: impl FnMut(usize)) {
        if let Some(indices) = self.cells.get(&(cell_coord(x), cell_coord(z))) {
            for &index in indices {
                visit(index);
            }
        }
        for &index in &self.large_triangles {
            visit(index);
        }
    }

    fn for_aabb(
        &self,
        min_x: f32,
        max_x: f32,
        min_z: f32,
        max_z: f32,
        mut visit: impl FnMut(usize),
    ) {
        let (min_cell_x, max_cell_x) = (cell_coord(min_x), cell_coord(max_x));
        let (min_cell_z, max_cell_z) = (cell_coord(min_z), cell_coord(max_z));
        for cell_x in min_cell_x..=max_cell_x {
            for cell_z in min_cell_z..=max_cell_z {
                if let Some(indices) = self.cells.get(&(cell_x, cell_z)) {
                    for &index in indices {
                        let triangle_min = self.min_cells[index];
                        let first_overlap_x = min_cell_x.max(triangle_min.0);
                        let first_overlap_z = min_cell_z.max(triangle_min.1);
                        // Triângulos que aparecem em várias células consultadas são
                        // processados apenas na primeira célula de interseção.
                        if (cell_x, cell_z) == (first_overlap_x, first_overlap_z) {
                            visit(index);
                        }
                    }
                }
            }
        }
        for &index in &self.large_triangles {
            visit(index);
        }
    }
}

fn cell_coord(value: f32) -> i32 {
    (value / COLLISION_CELL_SIZE).floor() as i32
}

// 🗺️ Dados de colisão determinísticos do nível, divididos por classificação da normal
#[derive(Resource, Default)]
pub struct LevelCollision {
    pub floors: Vec<CollisionTriangle>,
    pub walls: Vec<CollisionTriangle>,
    pub ceilings: Vec<CollisionTriangle>,
    floor_grid: TriangleGrid,
    wall_grid: TriangleGrid,
    ceiling_grid: TriangleGrid,
    pub ready: bool,
}

impl LevelCollision {
    pub fn clear(&mut self) {
        self.floors.clear();
        self.walls.clear();
        self.ceilings.clear();
        self.floor_grid = TriangleGrid::default();
        self.wall_grid = TriangleGrid::default();
        self.ceiling_grid = TriangleGrid::default();
        self.ready = false;
    }

    fn rebuild_indices(&mut self) {
        self.floor_grid = TriangleGrid::build(&self.floors);
        self.wall_grid = TriangleGrid::build(&self.walls);
        self.ceiling_grid = TriangleGrid::build(&self.ceilings);
    }

    // Altura do piso mais alto sob (x, z) cujo Y seja <= max_y. Retorna (altura, normal).
    pub fn find_floor(&self, x: f32, z: f32, max_y: f32) -> Option<(f32, Vec3)> {
        let mut best: Option<(f32, Vec3)> = None;
        self.floor_grid.for_point(x, z, |index| {
            let tri = &self.floors[index];
            if let Some(y) = height_on_triangle(tri, x, z) {
                if y <= max_y && best.map_or(true, |(by, _)| y > by) {
                    best = Some((y, tri.normal));
                }
            }
        });
        best
    }

    // Altura do teto mais baixo sobre (x, z) cujo Y seja >= min_y.
    pub fn find_ceiling(&self, x: f32, z: f32, min_y: f32) -> Option<f32> {
        let mut best: Option<f32> = None;
        self.ceiling_grid.for_point(x, z, |index| {
            let tri = &self.ceilings[index];
            if let Some(y) = height_on_triangle(tri, x, z) {
                if y >= min_y && best.map_or(true, |by| y < by) {
                    best = Some(y);
                }
            }
        });
        best
    }

    // Empurra um ponto/esfera para fora das paredes. Retorna a normal acumulada dos empurrões.
    pub fn push_out_of_walls(&self, pos: &mut Vec3, radius: f32) -> Vec3 {
        let mut pushed = Vec3::ZERO;
        self.wall_grid.for_aabb(
            pos.x - radius,
            pos.x + radius,
            pos.z - radius,
            pos.z + radius,
            |index| {
                let tri = &self.walls[index];
                // Barreira barata antes do cálculo de ponto mais próximo no triângulo.
                if pos.x + radius < tri.a.x.min(tri.b.x).min(tri.c.x)
                    || pos.x - radius > tri.a.x.max(tri.b.x).max(tri.c.x)
                    || pos.z + radius < tri.a.z.min(tri.b.z).min(tri.c.z)
                    || pos.z - radius > tri.a.z.max(tri.b.z).max(tri.c.z)
                {
                    return;
                }
                let closest = closest_point_on_triangle(*pos, tri.a, tri.b, tri.c);
                let delta = *pos - closest;
                let dist = delta.length();
                if dist < radius {
                    // Direção de empurrão apenas no plano horizontal
                    let mut dir = if dist > 1e-5 {
                        delta / dist
                    } else {
                        tri.normal
                    };
                    dir.y = 0.0;
                    let dir = dir.normalize_or_zero();
                    if dir != Vec3::ZERO {
                        *pos += dir * (radius - dist);
                        pushed += dir;
                    }
                }
            },
        );
        pushed
    }
}

// Altura Y do plano do triângulo no ponto (x, z), se (x, z) estiver dentro da projeção XZ
fn height_on_triangle(tri: &CollisionTriangle, x: f32, z: f32) -> Option<f32> {
    let (a, b, c) = (tri.a, tri.b, tri.c);
    let d = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z);
    if d.abs() < 1e-8 {
        return None;
    }
    let l1 = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d;
    let l2 = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d;
    let l3 = 1.0 - l1 - l2;
    let eps = -1e-4;
    if l1 < eps || l2 < eps || l3 < eps {
        return None;
    }
    Some(l1 * a.y + l2 * b.y + l3 * c.y)
}

// Ponto mais próximo em um triângulo (Ericson, Real-Time Collision Detection)
fn closest_point_on_triangle(p: Vec3, a: Vec3, b: Vec3, c: Vec3) -> Vec3 {
    let ab = b - a;
    let ac = c - a;
    let ap = p - a;
    let d1 = ab.dot(ap);
    let d2 = ac.dot(ap);
    if d1 <= 0.0 && d2 <= 0.0 {
        return a;
    }

    let bp = p - b;
    let d3 = ab.dot(bp);
    let d4 = ac.dot(bp);
    if d3 >= 0.0 && d4 <= d3 {
        return b;
    }

    let vc = d1 * d4 - d3 * d2;
    if vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0 {
        return a + ab * (d1 / (d1 - d3));
    }

    let cp = p - c;
    let d5 = ab.dot(cp);
    let d6 = ac.dot(cp);
    if d6 >= 0.0 && d5 <= d6 {
        return c;
    }

    let vb = d5 * d2 - d1 * d6;
    if vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0 {
        return a + ac * (d2 / (d2 - d6));
    }

    let va = d3 * d6 - d5 * d4;
    if va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0 {
        return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)));
    }

    let denom = 1.0 / (va + vb + vc);
    a + ab * (vb * denom) + ac * (vc * denom)
}

// 📦 Plugin que extrai a malha do nível carregado pelo Blenvy e monta a colisão
pub struct CollisionPlugin;

impl Plugin for CollisionPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<LevelCollision>()
            .add_systems(PostUpdate, build_level_collision);
    }
}

// Reconstrói a colisão apenas a partir de malhas marcadas como TerrainMesh
fn build_level_collision(
    mut collision: ResMut<LevelCollision>,
    meshes: Res<Assets<Mesh>>,
    added: Query<(), Added<TerrainMesh>>,
    mut removed_levels: RemovedComponents<LevelRoot>,
    level_meshes: Query<(&Handle<Mesh>, &GlobalTransform), (With<TerrainMesh>, Without<Player>)>,
    mut frames_waiting: Local<Option<u32>>,
) {
    // Se a fase foi descarregada, limpa a colisão anterior imediatamente
    if removed_levels.read().next().is_some() {
        collision.clear();
    }

    if !added.is_empty() {
        *frames_waiting = Some(0);
    }
    let Some(frames) = *frames_waiting else {
        return;
    };
    if frames < 2 {
        *frames_waiting = Some(frames + 1);
        return;
    }
    *frames_waiting = None;

    let mut floors = Vec::new();
    let mut walls = Vec::new();
    let mut ceilings = Vec::new();

    for (handle, global) in &level_meshes {
        let Some(mesh) = meshes.get(handle) else {
            continue;
        };
        let Some(VertexAttributeValues::Float32x3(positions)) =
            mesh.attribute(Mesh::ATTRIBUTE_POSITION)
        else {
            continue;
        };

        let matrix = global.compute_matrix();
        let mut add_triangle = |i0: usize, i1: usize, i2: usize| {
            let a = matrix.transform_point3(Vec3::from(positions[i0]));
            let b = matrix.transform_point3(Vec3::from(positions[i1]));
            let c = matrix.transform_point3(Vec3::from(positions[i2]));
            let normal = (b - a).cross(c - a).normalize_or_zero();
            if normal == Vec3::ZERO {
                return;
            }

            let t = CollisionTriangle { a, b, c, normal };
            if normal.y > FLOOR_NORMAL_MIN_Y {
                floors.push(t);
            } else if normal.y < CEILING_NORMAL_MAX_Y {
                ceilings.push(t);
            } else {
                walls.push(t);
            }
        };

        match mesh.indices() {
            Some(Indices::U16(indices)) => {
                for tri in indices.chunks_exact(3) {
                    add_triangle(tri[0] as usize, tri[1] as usize, tri[2] as usize);
                }
            }
            Some(Indices::U32(indices)) => {
                for tri in indices.chunks_exact(3) {
                    add_triangle(tri[0] as usize, tri[1] as usize, tri[2] as usize);
                }
            }
            None => {
                for (base, _) in positions.chunks_exact(3).enumerate() {
                    let i = base * 3;
                    add_triangle(i, i + 1, i + 2);
                }
            }
        }
    }

    info!(
        "Colisão do nível: {} pisos, {} paredes, {} tetos",
        floors.len(),
        walls.len(),
        ceilings.len()
    );
    collision.ready = !(floors.is_empty() && walls.is_empty() && ceilings.is_empty());
    collision.floors = floors;
    collision.walls = walls;
    collision.ceilings = ceilings;
    collision.rebuild_indices();
}

#[cfg(test)]
mod tests {
    use super::*;

    fn triangle(a: Vec3, b: Vec3, c: Vec3) -> CollisionTriangle {
        CollisionTriangle {
            a,
            b,
            c,
            normal: Vec3::Y,
        }
    }

    #[test]
    fn point_grid_returns_triangles_covering_positive_and_negative_cells() {
        let triangles = vec![
            triangle(
                Vec3::new(-4.5, 0.0, -4.5),
                Vec3::new(-3.5, 0.0, -4.5),
                Vec3::new(-4.5, 0.0, -3.5),
            ),
            triangle(
                Vec3::new(8.0, 0.0, 8.0),
                Vec3::new(9.0, 0.0, 8.0),
                Vec3::new(8.0, 0.0, 9.0),
            ),
        ];
        let grid = TriangleGrid::build(&triangles);
        let mut found = Vec::new();
        grid.for_point(-4.0, -4.0, |index| found.push(index));
        assert!(found.contains(&0));
        assert!(!found.contains(&1));

        found.clear();
        grid.for_point(8.25, 8.25, |index| found.push(index));
        assert_eq!(found, vec![1]);
    }

    #[test]
    fn wall_aabb_query_visits_each_candidate_once_and_keeps_large_triangles() {
        let triangles = vec![
            triangle(
                Vec3::new(0.0, 0.0, 0.0),
                Vec3::new(9.0, 0.0, 0.0),
                Vec3::new(0.0, 0.0, 9.0),
            ),
            triangle(
                Vec3::new(-100.0, 0.0, -100.0),
                Vec3::new(100.0, 0.0, -100.0),
                Vec3::new(0.0, 0.0, 100.0),
            ),
        ];
        let grid = TriangleGrid::build(&triangles);
        assert!(grid.large_triangles.contains(&1));

        let mut found = Vec::new();
        grid.for_aabb(3.5, 4.5, 3.5, 4.5, |index| found.push(index));
        found.sort_unstable();
        assert_eq!(found, vec![0, 1]);
    }
}
