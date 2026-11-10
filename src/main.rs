mod camera;
mod collision;
mod display;
mod interaction;
mod player;
mod terrain;

use bevy::prelude::*;
use blenvy::BlenvyPlugin;
use camera::LakituCameraPlugin;
use collision::CollisionPlugin;
use display::{
    DisplayPlugin, DISABLE_MSAA, WINDOW_HEIGHT, WINDOW_RESIZABLE, WINDOW_TITLE, WINDOW_WIDTH,
};
use interaction::InteractionPlugin;
use player::PlayerPlugin;
use terrain::TerrainPlugin;

fn main() {
    let mut app = App::new();

    // 💡 Luz ambiente global que preenche as sombras com cores vivas e sem áreas pretas
    app.insert_resource(AmbientLight {
        color: Color::WHITE,
        brightness: 2200.0,
    });

    // 👾 Desativação opcional de MSAA configurada em display.rs (estética retrô pontual)
    if DISABLE_MSAA {
        app.insert_resource(Msaa::Off);
    }

    // 📺 Janela e plugins padrão configurados via display.rs
    app.add_plugins(
        DefaultPlugins
            .set(WindowPlugin {
                primary_window: Some(Window {
                    title: WINDOW_TITLE.into(),
                    resolution: bevy::window::WindowResolution::new(WINDOW_WIDTH, WINDOW_HEIGHT),
                    resizable: WINDOW_RESIZABLE,
                    ..default()
                }),
                ..default()
            })
            .set(ImagePlugin::default_nearest()),
    )
    .add_plugins(BlenvyPlugin::default())
    // 📺 Sistema de exibição e canvas de vídeo (display.rs)
    .add_plugins(DisplayPlugin)
    // 🏔️ Gerenciador de fases e ciclo de vida dos terrenos
    .add_plugins(TerrainPlugin)
    // 🧱 Colisão estática determinística (Piso / Parede / Teto) estilo SM64
    .add_plugins(CollisionPlugin)
    // 💥 Sistema de objetos interativos (inimigos, moedas, obstáculos dinâmicos)
    .add_plugins(InteractionPlugin)
    // 🎥 Câmera orbital estilo Lakitu
    .add_plugins(LakituCameraPlugin)
    // 🏃 Jogador e física de movimentação
    .add_plugins(PlayerPlugin)
    // 🔄 Inicialização encadeada: cria o canvas primeiro, depois instancia a câmera 3D acoplada a ele
    .add_systems(
        Startup,
        (
            display::setup_display_canvas,
            camera::spawn_camera,
            setup_scene,
        )
            .chain(),
    )
    .run();
}

fn setup_scene(mut commands: Commands) {
    // ☀️ Luz direcional (iluminação limpa estilo sol sem sombras difusas modernas) na Layer 0
    commands.spawn((
        DirectionalLightBundle {
            directional_light: DirectionalLight {
                shadows_enabled: false,
                illuminance: 6000.0,
                color: Color::WHITE,
                ..default()
            },
            transform: Transform::from_xyz(10.0, 20.0, 10.0).looking_at(Vec3::ZERO, Vec3::Y),
            ..default()
        },
        display::PIXEL_PERFECT_LAYER,
    ));
}
