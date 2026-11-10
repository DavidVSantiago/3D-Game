use bevy::prelude::*;
use bevy::render::mesh::{Indices, VertexAttributeValues};
use crate::player::Player;
use crate::terrain::{LevelRoot, TerrainMesh};

// Limiar da componente Y da normal para classificar triângulos (estilo SM64)
const FLOOR_NORMAL_MIN_Y: f32 = 0.5;
const CEILING_NORMAL_MAX_Y: f32 = -0.5;

// 🔺 Triângulo estático em espaço de mundo com normal pré-calculada
#[derive(Clone, Copy)]
pub struct CollisionTriangle {
    pub a: Vec3,
    pub b: Vec3,
    pub c: Vec3,
    pub normal: Vec3,
}

// 🗺️ Dados de colisão determinísticos do nível, divididos por classificação da normal
#[derive(Resource, Default)]
pub struct LevelCollision {
    pub floors: Vec<CollisionTriangle>,
    pub walls: Vec<CollisionTriangle>,
    pub ceilings: Vec<CollisionTriangle>,
    pub ready: bool,
}

impl LevelCollision {
    pub fn clear(&mut self) {
        self.floors.clear();
        self.walls.clear();
        self.ceilings.clear();
        self.ready = false;
    }

    // Altura do piso mais alto sob (x, z) cujo Y seja <= max_y. Retorna (altura, normal).
    pub fn find_floor(&self, x: f32, z: f32, max_y: f32) -> Option<(f32, Vec3)> {
        let mut best: Option<(f32, Vec3)> = None;
        for tri in &self.floors {
            if let Some(y) = height_on_triangle(tri, x, z) {
                if y <= max_y && best.map_or(true, |(by, _)| y > by) {
                    best = Some((y, tri.normal));
                }
            }
        }
        best
    }

    // Altura do teto mais baixo sobre (x, z) cujo Y seja >= min_y.
    pub fn find_ceiling(&self, x: f32, z: f32, min_y: f32) -> Option<f32> {
        let mut best: Option<f32> = None;
        for tri in &self.ceilings {
            if let Some(y) = height_on_triangle(tri, x, z) {
                if y >= min_y && best.map_or(true, |by| y < by) {
                    best = Some(y);
                }
            }
        }
        best
    }

    // Empurra um ponto/esfera para fora das paredes. Retorna a normal acumulada dos empurrões.
    pub fn push_out_of_walls(&self, pos: &mut Vec3, radius: f32) -> Vec3 {
        let mut pushed = Vec3::ZERO;
        for tri in &self.walls {
            let closest = closest_point_on_triangle(*pos, tri.a, tri.b, tri.c);
            let delta = *pos - closest;
            let dist = delta.length();
            if dist < radius {
                // Direção de empurrão apenas no plano horizontal
                let mut dir = if dist > 1e-5 { delta / dist } else { tri.normal };
                dir.y = 0.0;
                let dir = dir.normalize_or_zero();
                if dir != Vec3::ZERO {
                    *pos += dir * (radius - dist);
                    pushed += dir;
                }
            }
        }
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
    if d1 <= 0.0 && d2 <= 0.0 { return a; }

    let bp = p - b;
    let d3 = ab.dot(bp);
    let d4 = ac.dot(bp);
    if d3 >= 0.0 && d4 <= d3 { return b; }

    let vc = d1 * d4 - d3 * d2;
    if vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0 {
        return a + ab * (d1 / (d1 - d3));
    }

    let cp = p - c;
    let d5 = ab.dot(cp);
    let d6 = ac.dot(cp);
    if d6 >= 0.0 && d5 <= d6 { return c; }

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
    let Some(frames) = *frames_waiting else { return; };
    if frames < 2 {
        *frames_waiting = Some(frames + 1);
        return;
    }
    *frames_waiting = None;

    let mut floors = Vec::new();
    let mut walls = Vec::new();
    let mut ceilings = Vec::new();

    for (handle, global) in &level_meshes {
        let Some(mesh) = meshes.get(handle) else { continue; };
        let Some(VertexAttributeValues::Float32x3(positions)) =
            mesh.attribute(Mesh::ATTRIBUTE_POSITION) else { continue; };

        let indices: Vec<u32> = match mesh.indices() {
            Some(Indices::U16(i)) => i.iter().map(|&v| v as u32).collect(),
            Some(Indices::U32(i)) => i.clone(),
            None => (0..positions.len() as u32).collect(),
        };

        let matrix = global.compute_matrix();
        for tri in indices.chunks_exact(3) {
            let a = matrix.transform_point3(Vec3::from(positions[tri[0] as usize]));
            let b = matrix.transform_point3(Vec3::from(positions[tri[1] as usize]));
            let c = matrix.transform_point3(Vec3::from(positions[tri[2] as usize]));
            let normal = (b - a).cross(c - a).normalize_or_zero();
            if normal == Vec3::ZERO { continue; }

            let t = CollisionTriangle { a, b, c, normal };
            if normal.y > FLOOR_NORMAL_MIN_Y {
                floors.push(t);
            } else if normal.y < CEILING_NORMAL_MAX_Y {
                ceilings.push(t);
            } else {
                walls.push(t);
            }
        }
    }

    info!(
        "Colisão do nível: {} pisos, {} paredes, {} tetos",
        floors.len(), walls.len(), ceilings.len()
    );
    collision.ready = !(floors.is_empty() && walls.is_empty() && ceilings.is_empty());
    collision.floors = floors;
    collision.walls = walls;
    collision.ceilings = ceilings;
}
