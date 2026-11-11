use bevy::input::mouse::{MouseMotion, MouseWheel};
use bevy::prelude::*;
use bevy::render::camera::RenderTarget;
use crate::scene::player::Player;
use crate::settings::display::{ENABLE_FXAA, PIXEL_PERFECT_LAYER, RetroCanvasTarget, SKY_COLOR};

// 🎥 Configuração e estado da Câmera estilo Lakitu (Super Mario 64)
#[derive(Component)]
pub struct LakituCamera {
    pub distance: f32,          // Distância orbital do foco
    pub height: f32,            // Altura relativa acima do foco
    pub focus_offset_y: f32,    // Offset vertical do ponto mirado no jogador
    pub yaw: f32,               // Ângulo horizontal orbital em radianos
    pub pitch: f32,             // Ângulo vertical orbital em radianos
    pub follow_speed: f32,      // Suavização do movimento de perseguição
    pub rotation_speed: f32,    // Velocidade de giro manual por teclas
    pub mouse_sensitivity: f32, // Sensibilidade do mouse ao segurar botão direito
    pub current_focus: Vec3,    // Posição suavizada do foco atual
}

impl Default for LakituCamera {
    fn default() -> Self {
        Self {
            distance: 16.0,
            height: 4.0,
            focus_offset_y: 0.8,
            yaw: 0.0,
            pitch: 0.22, // Ligeiramente inclinada para baixo para boa visão do nível
            follow_speed: 6.0,
            rotation_speed: 2.4,
            mouse_sensitivity: 0.004,
            current_focus: Vec3::ZERO,
        }
    }
}

// 📦 Plugin da Câmera Lakitu
pub struct LakituCameraPlugin;

impl Plugin for LakituCameraPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(PostUpdate, lakitu_camera_system);
    }
}

// 🎯 Instancia a câmera 3D Lakitu renderizando diretamente no Canvas de vídeo
pub fn spawn_camera(
    mut commands: Commands,
    canvas_target: Res<RetroCanvasTarget>,
) {
    let default_cam = LakituCamera::default();

    let horizontal_dist = default_cam.distance * default_cam.pitch.cos();
    let eye = Vec3::new(
        horizontal_dist * default_cam.yaw.sin(),
        default_cam.height + default_cam.distance * default_cam.pitch.sin(),
        horizontal_dist * default_cam.yaw.cos(),
    );

    let camera_entity = commands.spawn((
        Camera3dBundle {
            camera: Camera {
                order: -1, // Renderiza ANTES da câmera de exibição da janela
                target: RenderTarget::Image(canvas_target.0.clone()),
                clear_color: ClearColorConfig::Custom(SKY_COLOR), // Céu azul vibrante
                ..default()
            },
            transform: Transform::from_translation(eye).looking_at(Vec3::ZERO, Vec3::Y),
            ..default()
        },
        default_cam,
        PIXEL_PERFECT_LAYER,
    )).id();

    if ENABLE_FXAA {
        commands.entity(camera_entity).insert(bevy::core_pipeline::fxaa::Fxaa::default());
    }
}

// 🎮 Sistema de controle e perseguição suave estilo Lakitu
pub fn lakitu_camera_system(
    time: Res<Time>,
    keyboard_input: Res<ButtonInput<KeyCode>>,
    mouse_button: Res<ButtonInput<MouseButton>>,
    mut mouse_motion_events: EventReader<MouseMotion>,
    mut mouse_wheel_events: EventReader<MouseWheel>,
    player_query: Query<&Transform, (With<Player>, Without<LakituCamera>)>,
    mut camera_query: Query<(&mut LakituCamera, &mut Transform)>,
) {
    let Ok(player_transform) = player_query.get_single() else { return; };
    let Ok((mut camera, mut camera_transform)) = camera_query.get_single_mut() else { return; };

    let dt = time.delta_seconds();
    if dt <= 0.0 { return; }

    // 1. Rotação manual por teclas: Q/E ou Setas Esquerda/Direita
    if keyboard_input.pressed(KeyCode::KeyQ) || keyboard_input.pressed(KeyCode::ArrowLeft) {
        camera.yaw += camera.rotation_speed * dt;
    }
    if keyboard_input.pressed(KeyCode::KeyE) || keyboard_input.pressed(KeyCode::ArrowRight) {
        camera.yaw -= camera.rotation_speed * dt;
    }

    // 2. Botão R: Recentraliza a câmera instantaneamente atrás do personagem (como no SM64)
    if keyboard_input.just_pressed(KeyCode::KeyR) {
        let facing = player_transform.rotation * Vec3::Y;
        let target_yaw = (-facing.x).atan2(-facing.z);
        camera.yaw = target_yaw;
    }

    // 3. Controle por mouse: segurar botão direito e arrastar para girar
    if mouse_button.pressed(MouseButton::Right) {
        for ev in mouse_motion_events.read() {
            camera.yaw -= ev.delta.x * camera.mouse_sensitivity;
            camera.pitch = (camera.pitch + ev.delta.y * camera.mouse_sensitivity)
                .clamp(-0.05, 1.1); // Trava para não inverter nem entrar no chão
        }
    } else {
        mouse_motion_events.clear();
    }

    // 4. Zoom na câmera com a roda do mouse (Scroll Wheel)
    for ev in mouse_wheel_events.read() {
        camera.distance = (camera.distance - ev.y * 1.2).clamp(6.0, 30.0);
    }

    // 5. Suavização do ponto de foco (acompanha o jogador sem 'trancos')
    let target_focus = player_transform.translation + Vec3::Y * camera.focus_offset_y;
    let focus_t = (camera.follow_speed * dt).clamp(0.0, 1.0);
    camera.current_focus = camera.current_focus.lerp(target_focus, focus_t);

    // 6. Cálculo da posição orbital da câmera
    let horizontal_dist = camera.distance * camera.pitch.cos();
    let offset = Vec3::new(
        horizontal_dist * camera.yaw.sin(),
        camera.height + camera.distance * camera.pitch.sin(),
        horizontal_dist * camera.yaw.cos(),
    );
    let desired_pos = camera.current_focus + offset;

    // 7. Interpolação suave da posição da câmera e orientação para o ponto de foco
    camera_transform.translation = camera_transform.translation.lerp(desired_pos, focus_t);
    camera_transform.look_at(camera.current_focus, Vec3::Y);
}
