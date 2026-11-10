use bevy::prelude::*;
use crate::collision::LevelCollision;
use crate::interaction::{CollectibleKind, ItemCollectedEvent, PlayerDamageEvent};

// 📏 Dimensões do corpo do jogador (cone de 1.2 de altura e raio 0.5, origem no centro)
const PLAYER_HALF_HEIGHT: f32 = 0.6;
const PLAYER_RADIUS: f32 = 0.5;
const STEP_HEIGHT: f32 = 0.5; // Maior degrau que o jogador sobe sem pular
const VOID_Y: f32 = -30.0;    // Abaixo disso o jogador reaparece
const SPAWN_POSITION: Vec3 = Vec3::new(0.0, 10.0, 0.0);

// 🏃 Marcador do jogador para os sistemas encontrarem a entidade
#[derive(Component)]
pub struct Player;

// ❤️ Estatísticas e estado de saúde do jogador
#[derive(Component)]
pub struct PlayerStats {
    pub health: u32,
    pub max_health: u32,
    pub coins: u32,
    pub invulnerability_timer: f32,
}

impl Default for PlayerStats {
    fn default() -> Self {
        Self {
            health: 8,       // 8 fatias de vida estilo Super Mario 64
            max_health: 8,
            coins: 0,
            invulnerability_timer: 0.0,
        }
    }
}

// ⚙️ Componente com todos os dados e parâmetros de física do personagem
#[derive(Component)]
pub struct PlayerController {
    // 🏎️ Física horizontal (Plano XZ)
    pub velocity: Vec3,          // Velocidade vetorial total (X, Y, Z)
    pub max_speed: f32,         // Velocidade máxima horizontal de corrida
    pub acceleration: f32,      // Taxa de aceleração horizontal no chão
    pub deceleration: f32,      // Desaceleração por atrito quando solta os controles
    pub turn_speed: f32,        // Rapidez com que a inércia faz a curva no chão
    pub skid_deceleration: f32, // Desaceleração rápida ao inverter bruscamente a direção

    // 🦘 Gravidade e Salto (Eixo Y)
    pub is_grounded: bool,       // Indica se o personagem está em contato com o solo
    pub gravity: f32,            // Aceleração gravitacional contínua
    pub jump_impulse: f32,       // Impulso vertical instantâneo do salto
    pub terminal_velocity: f32,  // Velocidade máxima de queda livre
    pub air_control_factor: f32, // Eficiência de movimentação e curva no ar (0.0 a 1.0)
    pub jump_cut_factor: f32,    // Multiplicador ao soltar o botão de salto prematuramente

    // 🎭 Orientação visual e inclinação do corpo no terreno
    pub facing_yaw: f32,         // Direção para onde o personagem olha (rotação em Y)
    pub tilt: Quat,              // Inclinação atual (suavizada) do corpo
    pub tilt_strength: f32,      // Fração da inclinação real do terreno aplicada ao corpo (0.0 a 1.0)
    pub max_tilt_angle: f32,     // Limite superior da inclinação em radianos
    pub tilt_smoothing: f32,     // Rapidez da transição da inclinação
}

impl Default for PlayerController {
    fn default() -> Self {
        Self {
            velocity: Vec3::ZERO,
            max_speed: 7.0,
            acceleration: 15.0,
            deceleration: 20.0,
            turn_speed: 28.0,
            skid_deceleration: 32.0,

            is_grounded: false,
            gravity: 30.0,
            jump_impulse: 12.0,
            terminal_velocity: -35.0,
            air_control_factor: 0.65,
            jump_cut_factor: 0.5,

            facing_yaw: 0.0,
            tilt: Quat::IDENTITY,
            tilt_strength: 0.6,
            max_tilt_angle: 0.28, // ~16°
            tilt_smoothing: 10.0,
        }
    }
}

// 📦 Plugin que encapsula todo o ciclo de vida e sistemas do personagem
pub struct PlayerPlugin;

impl Plugin for PlayerPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, spawn_player)
            .add_systems(
                Update,
                (
                    player_movement_system,
                    handle_player_damage_system,
                    handle_player_collectibles_system,
                    player_invulnerability_system,
                ),
            );
    }
}

// 🎯 Instancia o jogador na cena
pub fn spawn_player(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    commands.spawn((
        PbrBundle {
            mesh: meshes.add(Cone {
                radius: 0.5,
                height: 1.2,
            }),
            material: materials.add(StandardMaterial {
                base_color: Color::srgb(0.95, 0.12, 0.12),
                // Estilo Nintendo DS: difuso puro, zero brilho especular / Phong
                perceptual_roughness: 1.0,
                reflectance: 0.0,
                metallic: 0.0,
                ..default()
            }),
            // Rotação de -90° em X para a ponta do cone mirar no eixo frontal (-Z)
            // Nasce no alto e cai até o terreno assim que a colisão estiver pronta
            transform: Transform::from_translation(SPAWN_POSITION)
                .with_rotation(Quat::from_rotation_x(-std::f32::consts::FRAC_PI_2)),
            ..default()
        },
        Player,
        PlayerController::default(),
        PlayerStats::default(),
    ));
}

// 🎮 Sistema integrado de física: inércia horizontal, gravidade, salto e atrito
pub fn player_movement_system(
    keyboard_input: Res<ButtonInput<KeyCode>>,
    time: Res<Time>,
    camera_query: Query<&Transform, (With<Camera3d>, Without<Player>)>,
    mut player_query: Query<(&mut PlayerController, &mut Transform), With<Player>>,
    collision: Res<LevelCollision>,
) {
    let Ok(camera_transform) = camera_query.get_single() else { return; };
    let Ok((mut controller, mut player_transform)) = player_query.get_single_mut() else { return; };

    let dt = time.delta_seconds();
    if dt <= 0.0 { return; }

    // Aguarda a colisão do nível ser construída antes de aplicar a física (evita cair no vazio)
    if !collision.ready { return; }
    // Evita saltos enormes no primeiro quadro após carregamento
    let dt = dt.min(1.0 / 20.0);

    // 1. Vetores direcionais da câmera projetados no plano horizontal (XZ)
    let mut forward = camera_transform.forward().as_vec3();
    let mut right = camera_transform.right().as_vec3();
    forward.y = 0.0;
    right.y = 0.0;

    let forward = forward.normalize_or_zero();
    let right = right.normalize_or_zero();

    // 2. Mapeamento dos comandos de direção (WASD)
    let mut input_dir = Vec3::ZERO;
    if keyboard_input.pressed(KeyCode::KeyW) { input_dir += forward; }
    if keyboard_input.pressed(KeyCode::KeyS) { input_dir -= forward; }
    if keyboard_input.pressed(KeyCode::KeyD) { input_dir += right; }
    if keyboard_input.pressed(KeyCode::KeyA) { input_dir -= right; }

    let input_dir = input_dir.normalize_or_zero();
    let has_input = input_dir.length_squared() > 0.0;

    // 3. Gravidade e Mecânica de Salto (Eixo Y)
    if controller.is_grounded {
        if keyboard_input.just_pressed(KeyCode::Space) {
            controller.velocity.y = controller.jump_impulse;
            controller.is_grounded = false;
        }
    } else {
        // Aceleração da gravidade puxando para baixo
        controller.velocity.y -= controller.gravity * dt;
        if controller.velocity.y < controller.terminal_velocity {
            controller.velocity.y = controller.terminal_velocity;
        }

        // Salto com altura variável: soltar o Espaço durante a subida corta a velocidade vertical
        if controller.velocity.y > 0.0 && keyboard_input.just_released(KeyCode::Space) {
            controller.velocity.y *= controller.jump_cut_factor;
        }
    }

    // 4. Física Horizontal com Inércia (Plano XZ)
    let mut horiz_vel = Vec3::new(controller.velocity.x, 0.0, controller.velocity.z);
    let current_speed = horiz_vel.length();

    if has_input {
        // No ar, a aceleração é multiplicada pelo air_control_factor
        let accel = if controller.is_grounded {
            controller.acceleration
        } else {
            controller.acceleration * controller.air_control_factor
        };

        if current_speed > 0.5 {
            let vel_dir = horiz_vel / current_speed;
            let dot = vel_dir.dot(input_dir);

            // Derrapagem só ocorre quando em contato com o solo
            if controller.is_grounded && dot < -0.4 {
                let new_speed = (current_speed - controller.skid_deceleration * dt).max(0.0);
                if new_speed == 0.0 {
                    horiz_vel = Vec3::ZERO;
                } else {
                    horiz_vel = vel_dir * new_speed;
                }
            } else {
                // Curva com inércia: preserva momentum enquanto alinha o vetor suavemente
                let turn_speed = if controller.is_grounded {
                    controller.turn_speed
                } else {
                    controller.turn_speed * controller.air_control_factor
                };
                let turn_factor = (turn_speed * dt).clamp(0.0, 1.0);
                let steered_dir = vel_dir.lerp(input_dir, turn_factor).normalize_or_zero();
                let new_speed = (current_speed + accel * dt).min(controller.max_speed);
                horiz_vel = steered_dir * new_speed;
            }
        } else {
            // Saindo do repouso
            let new_speed = (current_speed + accel * dt).min(controller.max_speed);
            horiz_vel = input_dir * new_speed;
        }
    } else {
        // Desaceleração: no chão aplica o atrito normal; no ar há pouca resistência (arrasto suave)
        let decel = if controller.is_grounded {
            controller.deceleration
        } else {
            controller.deceleration * 0.25
        };

        if current_speed > 0.0 {
            let new_speed = (current_speed - decel * dt).max(0.0);
            if new_speed == 0.0 {
                horiz_vel = Vec3::ZERO;
            } else {
                horiz_vel = (horiz_vel / current_speed) * new_speed;
            }
        }
    }

    // Recompõe o vetor de velocidade total
    controller.velocity = Vec3::new(horiz_vel.x, controller.velocity.y, horiz_vel.z);

    // 5. Integração da posição no mundo
    let mut pos = player_transform.translation + controller.velocity * dt;

    // 6. Colisão com a malha do terreno (triângulos estáticos classificados pela normal)
    // 6a. Paredes: empurra o corpo para fora em duas alturas (joelho e peito)
    for offset in [-0.3_f32, 0.3] {
        let mut probe = Vec3::new(pos.x, pos.y + offset, pos.z);
        let before = probe;
        let pushed = collision.push_out_of_walls(&mut probe, PLAYER_RADIUS);
        pos.x += probe.x - before.x;
        pos.z += probe.z - before.z;

        // Remove a componente da velocidade horizontal que aponta contra a parede
        if pushed != Vec3::ZERO {
            let n = pushed.normalize();
            let into_wall = controller.velocity.dot(n);
            if into_wall < 0.0 {
                controller.velocity -= n * into_wall;
            }
        }
    }

    // 6b. Teto: bate a cabeça e cancela a subida
    let head_y = pos.y + PLAYER_HALF_HEIGHT;
    if controller.velocity.y > 0.0 {
        if let Some(ceiling_y) = collision.find_ceiling(pos.x, pos.z, player_transform.translation.y) {
            if head_y >= ceiling_y {
                pos.y = ceiling_y - PLAYER_HALF_HEIGHT;
                controller.velocity.y = 0.0;
            }
        }
    }

    // 6c. Piso: raio vertical para baixo a partir de um pouco acima dos pés
    let feet_y = pos.y - PLAYER_HALF_HEIGHT;
    let floor = collision.find_floor(pos.x, pos.z, feet_y + STEP_HEIGHT);

    let mut ground_normal = Vec3::Y;

    match floor {
        Some((floor_y, normal)) => {
            let snap_distance = STEP_HEIGHT + horiz_vel.length() * dt * 2.0;
            let falling = controller.velocity.y <= 0.0;

            if falling && feet_y <= floor_y {
                // Pousou (ou subiu um degrau): apoia os pés exatamente sobre o piso
                pos.y = floor_y + PLAYER_HALF_HEIGHT;
                controller.velocity.y = 0.0;
                controller.is_grounded = true;
                ground_normal = normal;
            } else if controller.is_grounded && falling && feet_y - floor_y <= snap_distance {
                // Descendo rampa: gruda no piso em vez de ficar "voando"
                pos.y = floor_y + PLAYER_HALF_HEIGHT;
                controller.velocity.y = 0.0;
                ground_normal = normal;
            } else {
                controller.is_grounded = false;
            }
        }
        None => controller.is_grounded = false,
    }

    // 6d. Queda no vazio: reaparece no ponto inicial
    if pos.y < VOID_Y {
        pos = SPAWN_POSITION;
        controller.velocity = Vec3::ZERO;
        controller.is_grounded = false;
    }

    player_transform.translation = pos;

    // 7. Rotação visual: direção (yaw) + inclinação sutil do corpo conforme o terreno
    // 7a. Yaw suave voltado para a direção horizontal do movimento (menor caminho angular)
    if horiz_vel.length_squared() > 0.05 {
        let move_dir = horiz_vel.normalize();
        let target_yaw = (-move_dir.x).atan2(-move_dir.z);
        let diff = (target_yaw - controller.facing_yaw + std::f32::consts::PI)
            .rem_euclid(std::f32::consts::TAU) - std::f32::consts::PI;
        let rotation_speed = 10.0;
        let t = (rotation_speed * dt).clamp(0.0, 1.0);
        controller.facing_yaw += diff * t;
    }

    // 7b. Inclinação estilo SM64: só a parte da inclinação do terreno na direção em que
    // o personagem olha (subida/descida). Em ladeira transversal a inclinação é zero.
    let facing = Vec3::new(-controller.facing_yaw.sin(), 0.0, -controller.facing_yaw.cos());
    let mut target_tilt = Quat::IDENTITY;
    if controller.is_grounded {
        let right = facing.cross(Vec3::Y);
        // Normal do piso sem a componente lateral: fica só o "pitch" ao longo do olhar
        let along = (ground_normal - right * ground_normal.dot(right)).normalize_or_zero();
        if along != Vec3::ZERO && along.y > 0.0 {
            let slope_angle = along.dot(facing).atan2(along.y);
            let tilt_angle = (slope_angle * controller.tilt_strength)
                .clamp(-controller.max_tilt_angle, controller.max_tilt_angle);
            target_tilt = Quat::from_axis_angle(Vec3::Y.cross(facing).normalize_or_zero(), tilt_angle);
        }
    }
    let tilt_t = (controller.tilt_smoothing * dt).clamp(0.0, 1.0);
    controller.tilt = controller.tilt.slerp(target_tilt, tilt_t);

    // Rotação final = inclinação * yaw * compensação do cone (ponta aponta para -Z)
    player_transform.rotation = controller.tilt
        * Quat::from_rotation_y(controller.facing_yaw)
        * Quat::from_rotation_x(-std::f32::consts::FRAC_PI_2);
}

// 💥 Reage ao dano sofrido por inimigos ou perigos
fn handle_player_damage_system(
    mut damage_events: EventReader<PlayerDamageEvent>,
    mut query: Query<(&mut PlayerStats, &mut PlayerController, &Transform), With<Player>>,
) {
    let Ok((mut stats, mut controller, transform)) = query.get_single_mut() else { return; };

    for ev in damage_events.read() {
        if stats.invulnerability_timer <= 0.0 {
            stats.health = stats.health.saturating_sub(ev.damage);
            stats.invulnerability_timer = 1.2; // 1.2s de invulnerabilidade

            // Impulso de Knockback (empurrão para longe da fonte de dano)
            let mut knockback_dir = transform.translation - ev.source_pos;
            knockback_dir.y = 0.0;
            let knockback_dir = knockback_dir.normalize_or_zero();

            controller.velocity = knockback_dir * ev.knockback + Vec3::Y * 5.0;
            controller.is_grounded = false;

            info!("💥 Jogador atingido! Dano: {}, Vida restante: {}", ev.damage, stats.health);
        }
    }
}

// 🌟 Reage à coleta de itens no mapa
fn handle_player_collectibles_system(
    mut collect_events: EventReader<ItemCollectedEvent>,
    mut query: Query<&mut PlayerStats, With<Player>>,
) {
    let Ok(mut stats) = query.get_single_mut() else { return; };

    for ev in collect_events.read() {
        match &ev.kind {
            CollectibleKind::Coin => {
                stats.coins += ev.value;
                info!("🪙 Moeda coletada! Total: {}", stats.coins);
            }
            CollectibleKind::Heart => {
                stats.health = (stats.health + ev.value).min(stats.max_health);
                info!("❤️ Vida restaurada! Vida atual: {}", stats.health);
            }
            CollectibleKind::Star => {
                info!("⭐ Estrela coletada!");
            }
            CollectibleKind::Special(name) => {
                info!("🎁 Item especial obtido: {}!", name);
            }
        }
    }
}

// ✨ Efeito de piscar durante o período de invulnerabilidade
fn player_invulnerability_system(
    time: Res<Time>,
    mut query: Query<(&mut PlayerStats, &mut Visibility), With<Player>>,
) {
    let Ok((mut stats, mut visibility)) = query.get_single_mut() else { return; };

    if stats.invulnerability_timer > 0.0 {
        stats.invulnerability_timer -= time.delta_seconds();
        // Alterna visibilidade a cada 0.1s para piscar
        if (stats.invulnerability_timer * 10.0) as u32 % 2 == 0 {
            *visibility = Visibility::Hidden;
        } else {
            *visibility = Visibility::Visible;
        }
    } else {
        *visibility = Visibility::Visible;
    }
}
