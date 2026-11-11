mod scene;
mod settings;

use bevy::prelude::*;
use bevy::render::RenderPlugin;
use blenvy::BlenvyPlugin;
use scene::camera::camera::{self, LakituCameraPlugin};
use scene::objects::interaction::InteractionPlugin;
use scene::player::player::PlayerPlugin;
use scene::world::collision::CollisionPlugin;
use scene::world::terrain::TerrainPlugin;
use settings::diagnostics::{DiagnosticRenderConfig, DiagnosticsPlugin};
use settings::display::{
    self, DISABLE_MSAA, DisplayPlugin, WINDOW_HEIGHT, WINDOW_RESIZABLE, WINDOW_TITLE, WINDOW_WIDTH,
};

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

    // 🛠️ Carrega configurações de GPU, backend e VSync para testes de diagnóstico
    let diag_config = DiagnosticRenderConfig::load_configuration();
    let render_creation = diag_config.build_render_creation();

    // 🖼️ Plugin de imagem configurado conforme a preferência de textura (Nearest vs Linear/Anisotrópico)
    let image_plugin = match display::get_texture_filtering_mode() {
        display::TextureFilteringMode::Pixelated => ImagePlugin::default_nearest(),
        _ => ImagePlugin::default_linear(),
    };

    // 📺 Janela e plugins padrão configurados via display.rs e diagnostics.rs
    app.add_plugins(
        DefaultPlugins
            .set(WindowPlugin {
                primary_window: Some(Window {
                    title: WINDOW_TITLE.into(),
                    resolution: bevy::window::WindowResolution::new(WINDOW_WIDTH, WINDOW_HEIGHT),
                    resizable: WINDOW_RESIZABLE,
                    present_mode: diag_config.present_mode,
                    ..default()
                }),
                ..default()
            })
            .set(image_plugin)
            .set(RenderPlugin {
                render_creation,
                ..default()
            }),
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
    // ⏱️ Diagnóstico de hardware, GPU e monitoramento de frame pacing
    .add_plugins(DiagnosticsPlugin)
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
