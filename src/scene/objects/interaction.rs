use bevy::prelude::*;
use crate::scene::player::Player;

// 📦 Tipo de item coletável
#[allow(dead_code)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CollectibleKind {
    Coin,
    Star,
    Heart,
    Special(String),
}

// 🎯 Componente de Hitbox para objetos interativos
#[allow(dead_code)]
#[derive(Component, Clone, Copy, Debug)]
pub struct Hitbox {
    pub radius: f32,
    pub height: f32,
}

#[allow(dead_code)]
impl Hitbox {
    pub fn sphere(radius: f32) -> Self {
        Self { radius, height: radius * 2.0 }
    }

    pub fn cylinder(radius: f32, height: f32) -> Self {
        Self { radius, height }
    }
}

// 💥 Resposta da colisão com o objeto
#[allow(dead_code)]
#[derive(Component, Clone, Debug)]
pub enum Interactable {
    /// Inimigo / Espinho: causa dano ao jogador e knockback
    Hazard { damage: u32, knockback: f32 },
    /// Moeda, Estrela, Chave, Item especial: coletado e desaparece
    Collectible { kind: CollectibleKind, value: u32 },
    /// Obstáculo sólido dinâmico: empurra o jogador para fora (ex: caixas, pilares, barris)
    SolidObstacle,
    /// Zona de ativação de evento: checkpoints, portais, áreas secretas
    TriggerZone { id: String },
}

// 📢 Eventos disparados pelas colisões
#[derive(Event, Debug)]
pub struct PlayerDamageEvent {
    pub damage: u32,
    pub source_pos: Vec3,
    pub knockback: f32,
}

#[derive(Event, Debug)]
pub struct ItemCollectedEvent {
    pub kind: CollectibleKind,
    pub value: u32,
}

#[allow(dead_code)]
#[derive(Event, Debug)]
pub struct TriggerZoneEvent {
    pub id: String,
}

pub struct InteractionPlugin;

impl Plugin for InteractionPlugin {
    fn build(&self, app: &mut App) {
        app.add_event::<PlayerDamageEvent>()
            .add_event::<ItemCollectedEvent>()
            .add_event::<TriggerZoneEvent>()
            .add_systems(Update, player_interaction_system);
    }
}

// 🎮 Sistema que detecta a sobreposição entre o jogador e objetos interativos no mundo
fn player_interaction_system(
    mut commands: Commands,
    mut player_query: Query<(&mut Transform, &Player), Without<Hitbox>>,
    interactables_query: Query<(Entity, &GlobalTransform, &Hitbox, &Interactable)>,
    mut damage_events: EventWriter<PlayerDamageEvent>,
    mut collect_events: EventWriter<ItemCollectedEvent>,
    mut trigger_events: EventWriter<TriggerZoneEvent>,
) {
    let Ok((mut player_transform, _)) = player_query.get_single_mut() else { return; };
    let player_pos = player_transform.translation;
    let player_radius = 0.5;
    let player_feet = player_pos.y - 0.6;
    let player_head = player_pos.y + 0.6;

    for (entity, global, hitbox, interactable) in &interactables_query {
        let obj_pos = global.translation();
        let obj_feet = obj_pos.y - hitbox.height * 0.5;
        let obj_head = obj_pos.y + hitbox.height * 0.5;

        // Teste de sobreposição no eixo vertical Y
        let vertical_overlap = player_head >= obj_feet && player_feet <= obj_head;
        if !vertical_overlap { continue; }

        // Teste de distância no plano horizontal XZ
        let dx = player_pos.x - obj_pos.x;
        let dz = player_pos.z - obj_pos.z;
        let dist_sq = dx * dx + dz * dz;
        let min_dist = player_radius + hitbox.radius;

        if dist_sq < min_dist * min_dist {
            let dist = dist_sq.sqrt().max(1e-4);

            match interactable {
                Interactable::Hazard { damage, knockback } => {
                    damage_events.send(PlayerDamageEvent {
                        damage: *damage,
                        source_pos: obj_pos,
                        knockback: *knockback,
                    });
                }
                Interactable::Collectible { kind, value } => {
                    collect_events.send(ItemCollectedEvent {
                        kind: kind.clone(),
                        value: *value,
                    });
                    // O item coletado é removido do mundo
                    commands.entity(entity).despawn_recursive();
                }
                Interactable::SolidObstacle => {
                    // Empurra o jogador para fora do obstáculo dinâmico
                    let push_dir = Vec3::new(dx / dist, 0.0, dz / dist);
                    let overlap = min_dist - dist;
                    player_transform.translation += push_dir * overlap;
                }
                Interactable::TriggerZone { id } => {
                    trigger_events.send(TriggerZoneEvent {
                        id: id.clone(),
                    });
                }
            }
        }
    }
}
