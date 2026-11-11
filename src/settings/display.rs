use bevy::prelude::*;
use bevy::render::render_resource::{
    Extent3d, TextureDescriptor, TextureDimension, TextureFormat, TextureUsages,
};
use bevy::render::texture::{ImageAddressMode, ImageFilterMode, ImageSampler, ImageSamplerDescriptor};
use bevy::render::view::RenderLayers;
use bevy::window::PrimaryWindow;

// =========================================================================
// 🎛️ CONFIGURAÇÕES PRINCIPAIS DE VÍDEO E RESOLUÇÃO (EDITE AQUI!)
// =========================================================================
//
// 💡 TABELA DE PRESETS POPULARES:
// • 144p Widescreen (Padrão Nintendo DS 16:9): INTERNAL_WIDTH = 256,  INTERNAL_HEIGHT = 144
// • Nintendo DS Nativo (4:3):                  INTERNAL_WIDTH = 256,  INTERNAL_HEIGHT = 192
// • PS1 / Nintendo 64 (4:3):                   INTERNAL_WIDTH = 320,  INTERNAL_HEIGHT = 240
// • 240p Widescreen Retrô:                     INTERNAL_WIDTH = 426,  INTERNAL_HEIGHT = 240
// • 360p Retrô Leve:                           INTERNAL_WIDTH = 640,  INTERNAL_HEIGHT = 360
// • 480p SD Retrô:                             INTERNAL_WIDTH = 854,  INTERNAL_HEIGHT = 480
// • 720p HD (Sem Pixelation):                  INTERNAL_WIDTH = 1280, INTERNAL_HEIGHT = 720
// • 1080p Full HD Nativo:                      INTERNAL_WIDTH = 1920, INTERNAL_HEIGHT = 1080
// =========================================================================

/// 📺 Resolução interna da renderização 3D (Largura em pixels)
pub const INTERNAL_WIDTH: u32 = 854;

/// 📺 Resolução interna da renderização 3D (Altura em pixels)
pub const INTERNAL_HEIGHT: u32 = 480;

/// 🪟 Resolução inicial da janela no monitor (pode redimensionar livremente)
pub const WINDOW_WIDTH: f32 = 1280.0;
pub const WINDOW_HEIGHT: f32 = 720.0;

/// 🏷️ Título da janela do jogo
pub const WINDOW_TITLE: &str = "Retro 3D Platformer (DS Style)";

/// 🔲 Permitir que a janela seja redimensionada pelo usuário
pub const WINDOW_RESIZABLE: bool = true;

/// ☀️ Cor de fundo do céu na renderização 3D (estilo céu vibrante do Nintendo DS)
pub const SKY_COLOR: Color = Color::srgb(0.45, 0.75, 0.98);

/// ⬛ Cor das bordas letterbox / pillarbox fora do aspect ratio (quando redimensiona)
pub const LETTERBOX_COLOR: Color = Color::BLACK;

/// 👾 Desativar Anti-Aliasing Geométrico (MSAA):
/// true  = Bordas poligonais nítidas e pixeladas autênticas dos consoles retrô
/// false = Bordas suavizadas modernas (4x MSAA)
pub const DISABLE_MSAA: bool = false;

/// 🎨 Modo de Filtragem das Texturas (Anti-Aliasing do Chão, Terreno e Objetos):
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextureFilteringMode {
    /// 👾 Nearest-Neighbor: Pixels nítidos e quadrados (estilo Nintendo DS autêntico)
    Pixelated,
    /// 🌊 Linear: Interpolação bilinear/trilinear suave básica
    Linear,
    /// 💎 Anisotrópico 16x: Filtragem anisotrópica máxima (chão perfeitamente suave em ângulo rasante sem cintilação)
    Anisotropic16x,
}

/// 🎨 Filtragem ativa das texturas:
/// Alterne entre Anisotropic16x (chão suave e nítido) ou Pixelated (retrô pixel art)
/// 💡 Também pode ser sobrescrito via terminal: $env:TEXTURE_FILTERING="anisotropic" ou "pixelated"
pub const TEXTURE_FILTERING: TextureFilteringMode = TextureFilteringMode::Pixelated;

/// ✨ Anti-Aliasing de Pós-Processamento (FXAA) na Câmera 3D:
/// • true  = Suaviza a cena 3D inteira (arestas + interior de texturas)
/// • false = Desativado
pub const ENABLE_FXAA: bool = true;

/// 🎨 Forçar sombreamento cartunesco difuso (remove reflexos especulares plásticos Phong)
pub const REMOVE_SPECULAR_PHONG: bool = true;

/// Helper para obter o modo de filtragem de texturas respeitando variáveis de ambiente
pub fn get_texture_filtering_mode() -> TextureFilteringMode {
    if let Ok(val) = std::env::var("TEXTURE_FILTERING") {
        match val.to_lowercase().as_str() {
            "pixelated" | "nearest" | "retro" => TextureFilteringMode::Pixelated,
            "linear" | "smooth" => TextureFilteringMode::Linear,
            "anisotropic" | "af" | "aniso" | "16x" => TextureFilteringMode::Anisotropic16x,
            _ => TEXTURE_FILTERING,
        }
    } else {
        TEXTURE_FILTERING
    }
}

// =========================================================================
// 🚀 PREFERÊNCIAS DE GPU, DRIVER E VSYNC (INVESTIGAÇÃO DE STUTTER)
// =========================================================================

/// 🎮 Preferência de GPU:
/// • "high"     = (Recomendado no Windows) Força GPU Dedicada de Alta Performance (NVIDIA RTX 3060 Laptop)
/// • "low"      = Força GPU Integrada de Baixo Consumo (Intel(R) UHD Graphics)
/// • "software" = Força renderização por Software via CPU (WARP no Windows via DX12)
/// • "auto"     = Deixa o WGPU/Bevy decidir automaticamente
/// 💡 Também pode ser sobrescrito via terminal: $env:GPU_MODE="software" ou "integrated"
pub const GPU_MODE_PREFERENCE: &str = "high";

/// ⚡ Backend gráfico multiplataforma:
/// • "auto"   = (Padrão Inteligente) Seleciona a API ideal para cada SO:
///              • Windows -> DirectX 12 (Flip Model nativo DWM a 120Hz/144Hz sem micro-stutter)
///              • Linux   -> Vulkan (API nativa de alto desempenho)
///              • macOS   -> Metal (API nativa da Apple)
/// • "dx12"   = Força DirectX 12 (Windows)
/// • "vulkan" = Força Vulkan (Windows / Linux)
/// • "metal"  = Força Metal (macOS)
/// 💡 Também pode ser sobrescrito via terminal: $env:RENDER_BACKEND="vulkan"
pub const RENDER_BACKEND_PREFERENCE: &str = "auto";

/// 🔄 Sincronização Vertical (VSync):
/// • true  = PresentMode::Fifo (sincroniza com a taxa do monitor)
/// • false = PresentMode::AutoNoVsync (taxa de quadros livre)
/// 💡 Também pode ser sobrescrito via terminal: $env:VSYNC="off"
pub const ENABLE_VSYNC: bool = true;

/// 🎯 Limite de Taxa de Quadros (FPS Cap):
/// • Some(60.0) = Trava em 60 FPS cravados (padrão autêntico e suave de consoles)
/// • Some(30.0) = Trava em 30 FPS
/// • None        = Taxa livre (acompanha os Hz do monitor, ex: 120Hz, 144Hz)
/// 💡 Também pode ser sobrescrito via terminal: $env:TARGET_FPS="60" ou "none"
pub const TARGET_FPS: Option<f32> = Some(60.0);

// =========================================================================
// 🎨 CAMADAS DE RENDERIZAÇÃO (RENDER LAYERS)
// =========================================================================

/// Layer 0: O mundo 3D (terreno, personagem, luzes, câmera Lakitu 3D) renderizado na resolução interna
pub const PIXEL_PERFECT_LAYER: RenderLayers = RenderLayers::layer(0);

/// Layer 1: O canvas 2D e a câmera externa que desenha na janela com escala Nearest
pub const CANVAS_LAYER: RenderLayers = RenderLayers::layer(1);

// =========================================================================
// 📦 COMPONENTES E RECURSOS DO DISPLAY
// =========================================================================

/// Recurso global que armazena a textura offscreen onde o jogo 3D é desenhado
#[derive(Resource, Clone)]
pub struct RetroCanvasTarget(pub Handle<Image>);

/// Marcador do Sprite 2D que exibe a textura do canvas na tela
#[derive(Component)]
pub struct CanvasSprite;

/// Marcador da câmera 2D externa que projeta o Canvas na janela física
#[derive(Component)]
pub struct OuterCamera;

// =========================================================================
// 🚀 PLUGIN DO SISTEMA DE DISPLAY
// =========================================================================

pub struct DisplayPlugin;

impl Plugin for DisplayPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Update, fit_canvas)
            .add_systems(Update, enforce_retro_pixel_graphics);
    }
}

/// 🎯 Cria o canvas de renderização interna e a câmera 2D de exibição externa
pub fn setup_display_canvas(
    mut commands: Commands,
    mut images: ResMut<Assets<Image>>,
    windows: Query<&Window, With<PrimaryWindow>>,
) {
    let canvas_size = Extent3d {
        width: INTERNAL_WIDTH,
        height: INTERNAL_HEIGHT,
        depth_or_array_layers: 1,
    };

    // 1. Cria a textura offscreen de renderização interna com amostragem Nearest-Neighbor
    let mut canvas_image = Image {
        texture_descriptor: TextureDescriptor {
            label: Some("retro_canvas"),
            size: canvas_size,
            dimension: TextureDimension::D2,
            format: TextureFormat::Bgra8UnormSrgb,
            mip_level_count: 1,
            sample_count: 1,
            usage: TextureUsages::TEXTURE_BINDING
                | TextureUsages::COPY_DST
                | TextureUsages::RENDER_ATTACHMENT,
            view_formats: &[],
        },
        sampler: ImageSampler::Descriptor(ImageSamplerDescriptor {
            mag_filter: ImageFilterMode::Nearest,
            min_filter: ImageFilterMode::Nearest,
            mipmap_filter: ImageFilterMode::Nearest,
            address_mode_u: ImageAddressMode::ClampToEdge,
            address_mode_v: ImageAddressMode::ClampToEdge,
            address_mode_w: ImageAddressMode::ClampToEdge,
            ..default()
        }),
        ..default()
    };
    canvas_image.resize(canvas_size);

    let image_handle = images.add(canvas_image);

    // Registra o recurso global com o handle da textura do Canvas
    commands.insert_resource(RetroCanvasTarget(image_handle.clone()));

    // 2. Sprite 2D que projeta a textura do canvas na janela (Layer 1)
    commands.spawn((
        SpriteBundle {
            texture: image_handle,
            transform: Transform::from_xyz(0.0, 0.0, 0.0),
            ..default()
        },
        CanvasSprite,
        CANVAS_LAYER,
    ));

    // 3. Câmera 2D externa que exibe o Canvas e adiciona barras pretas (letterbox) se necessário
    let initial_scale = if let Ok(window) = windows.get_single() {
        let h_scale = window.width() / INTERNAL_WIDTH as f32;
        let v_scale = window.height() / INTERNAL_HEIGHT as f32;
        h_scale.min(v_scale).max(0.1)
    } else {
        1.0
    };

    let mut outer_camera = Camera2dBundle::default();
    outer_camera.camera.order = 1; // Renderiza DEPOIS do passe 3D
    outer_camera.camera.clear_color = ClearColorConfig::Custom(LETTERBOX_COLOR);
    // Preserva near: -1000.0 e far: 1000.0 para não recortar o plano do sprite em Z = 0
    outer_camera.projection.scale = 1.0 / initial_scale;

    commands.spawn((
        outer_camera,
        OuterCamera,
        CANVAS_LAYER,
    ));

    info!(
        "Display: Canvas interno inicializado em {}x{} (Escala inicial: {:.2}x)",
        INTERNAL_WIDTH, INTERNAL_HEIGHT, initial_scale
    );
}

/// 📐 Ajusta a projeção ortográfica automaticamente ao redimensionar a janela
pub fn fit_canvas(
    windows: Query<&Window, With<PrimaryWindow>>,
    mut projections: Query<&mut OrthographicProjection, With<OuterCamera>>,
    mut last_size: Local<Vec2>,
) {
    let Ok(window) = windows.get_single() else { return; };
    let current_size = Vec2::new(window.width(), window.height());
    if current_size == *last_size || current_size.x <= 0.0 || current_size.y <= 0.0 {
        return;
    }
    *last_size = current_size;

    let h_scale = current_size.x / INTERNAL_WIDTH as f32;
    let v_scale = current_size.y / INTERNAL_HEIGHT as f32;
    let scale = h_scale.min(v_scale).max(0.1);
    if let Ok(mut proj) = projections.get_single_mut() {
        proj.scale = 1.0 / scale;
        info!(
            "Display: Janela ajustada para ({:.0}x{:.0}), escala do canvas: {:.2}x",
            current_size.x, current_size.y, scale
        );
    }
}

/// 🎮 Controla a filtragem das texturas e iluminação dos materiais:
/// 1. Configura amostragem das texturas (Pixelated, Linear ou Anisotrópico 16x) mantendo Tiling (Repeat)
/// 2. Remove completamente brilho especular Phong (reflectance: 0, roughness: 1)
pub fn enforce_retro_pixel_graphics(
    mut image_events: EventReader<AssetEvent<Image>>,
    mut images: ResMut<Assets<Image>>,
    mut material_events: EventReader<AssetEvent<StandardMaterial>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let filtering_mode = get_texture_filtering_mode();
    let (mag_filter, min_filter, mipmap_filter, anisotropy_clamp) = match filtering_mode {
        TextureFilteringMode::Pixelated => (
            ImageFilterMode::Nearest,
            ImageFilterMode::Nearest,
            ImageFilterMode::Nearest,
            1,
        ),
        TextureFilteringMode::Linear => (
            ImageFilterMode::Linear,
            ImageFilterMode::Linear,
            ImageFilterMode::Linear,
            1,
        ),
        TextureFilteringMode::Anisotropic16x => (
            ImageFilterMode::Linear,
            ImageFilterMode::Linear,
            ImageFilterMode::Linear,
            16,
        ),
    };

    for event in image_events.read() {
        if let AssetEvent::Added { id } | AssetEvent::LoadedWithDependencies { id } | AssetEvent::Modified { id } = event {
            if let Some(image) = images.get(*id) {
                // Não altera o canvas interno (deve permanecer ClampToEdge e Nearest)
                if image.texture_descriptor.label == Some("retro_canvas") {
                    continue;
                }

                let is_same_filter = match (&image.sampler, filtering_mode) {
                    (ImageSampler::Descriptor(desc), TextureFilteringMode::Pixelated) => {
                        matches!(desc.mag_filter, ImageFilterMode::Nearest)
                            && matches!(desc.min_filter, ImageFilterMode::Nearest)
                            && matches!(desc.mipmap_filter, ImageFilterMode::Nearest)
                            && desc.anisotropy_clamp == 1
                            && matches!(desc.address_mode_u, ImageAddressMode::Repeat)
                    }
                    (ImageSampler::Descriptor(desc), TextureFilteringMode::Linear) => {
                        matches!(desc.mag_filter, ImageFilterMode::Linear)
                            && matches!(desc.min_filter, ImageFilterMode::Linear)
                            && matches!(desc.mipmap_filter, ImageFilterMode::Linear)
                            && desc.anisotropy_clamp == 1
                            && matches!(desc.address_mode_u, ImageAddressMode::Repeat)
                    }
                    (ImageSampler::Descriptor(desc), TextureFilteringMode::Anisotropic16x) => {
                        matches!(desc.mag_filter, ImageFilterMode::Linear)
                            && matches!(desc.min_filter, ImageFilterMode::Linear)
                            && matches!(desc.mipmap_filter, ImageFilterMode::Linear)
                            && desc.anisotropy_clamp == 16
                            && matches!(desc.address_mode_u, ImageAddressMode::Repeat)
                    }
                    _ => false,
                };

                let needs_update = !is_same_filter;

                if needs_update {
                    if let Some(image_mut) = images.get_mut(*id) {
                        match &mut image_mut.sampler {
                            ImageSampler::Descriptor(desc) => {
                                desc.mag_filter = mag_filter;
                                desc.min_filter = min_filter;
                                desc.mipmap_filter = mipmap_filter;
                                desc.anisotropy_clamp = anisotropy_clamp;
                                desc.address_mode_u = ImageAddressMode::Repeat;
                                desc.address_mode_v = ImageAddressMode::Repeat;
                                desc.address_mode_w = ImageAddressMode::Repeat;
                            }
                            ImageSampler::Default => {
                                image_mut.sampler = ImageSampler::Descriptor(ImageSamplerDescriptor {
                                    mag_filter,
                                    min_filter,
                                    mipmap_filter,
                                    anisotropy_clamp,
                                    address_mode_u: ImageAddressMode::Repeat,
                                    address_mode_v: ImageAddressMode::Repeat,
                                    address_mode_w: ImageAddressMode::Repeat,
                                    ..default()
                                });
                            }
                        }
                    }
                }
            }
        }
    }

    if REMOVE_SPECULAR_PHONG {
        for event in material_events.read() {
            if let AssetEvent::Added { id } | AssetEvent::LoadedWithDependencies { id } | AssetEvent::Modified { id } = event {
                if let Some(mat) = materials.get(*id) {
                    if mat.reflectance != 0.0 || mat.perceptual_roughness != 1.0 || mat.metallic != 0.0 {
                        if let Some(mat_mut) = materials.get_mut(*id) {
                            mat_mut.reflectance = 0.0;
                            mat_mut.perceptual_roughness = 1.0;
                            mat_mut.metallic = 0.0;
                        }
                    }
                }
            }
        }
    }
}
