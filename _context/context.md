# Documento de Contexto: Plataforma 3D Retrô (Blenvy + Bevy)

> **Finalidade deste documento:** Servir como fonte única da verdade sobre a arquitetura, decisões técnicas, problemas solucionados e estado atual do código para permitir que o desenvolvimento continue em qualquer outro computador sem perda de contexto.

---

## 1. Visão Geral e Direção Artística

* **Conceito:** Jogo de plataforma 3D retrô inspirado na estética e na física de *Super Mario 64* (especificamente a direção de arte e estilo do port para Nintendo DS: *Super Mario 64 DS*).
* **Direção Visual:**
  * **Renderização Interna em Baixa Resolução (Canvas Offscreen):** O mundo 3D é desenhado internamente em baixa resolução (padrão em 144p: `256 × 144` em 16:9 widescreen), e escalado para a janela física via **Nearest-Neighbor**, gerando pixels grandões, nítidos e bem definidos.
  * **Texturas Nítidas:** Todas as texturas são amostradas com ponto mais próximo (*Nearest-Neighbor* com modo *Repeat* habilitado), sem suavizações lineares ou borrões de mipmap.
  * **Iluminação Cartunesca Pura (Sem Phong/Specular):** Remoção de brilhos especulares plásticos (`reflectance = 0.0`, `perceptual_roughness = 1.0`, `metallic = 0.0`) com luz ambiente viva e luz direcional solar, recriando as cores chapadas e vibrantes do Nintendo DS.
  * **Bordas Poligonais Rígidas:** Anti-aliasing desativado (`Msaa::Off`) para que a silhueta dos modelos 3D apresente o serrilhado pixelizado autêntico da era retrô.
* **Paradigma de Desenvolvimento:** Baixo nível, código compilado nativo em Rust, ECS de alta performance com a engine Bevy (v0.14) integrada ao Blender via Blenvy.

---

## 2. Decisões Arquiteturais e Stack Escolhida

1. **Stack Central:** **Rust + Bevy 0.14.2 + Blenvy**.
   * O Blender atua como editor de fases e blueprints (geometria de terreno, posicionamento de objetos e entidades).
   * O Bevy consome as cenas `.glb` exportadas pelo Blenvy e executa toda a física, lógica de jogo, câmera e pipeline de renderização em código de máquina de altíssimo desempenho.
2. **Hierarquia Modular de Responsabilidades (`src/`):**
   * `src/main.rs`: Ponto de entrada e inicialização dos plugins e da esteira *Startup*.
   * `src/settings/`: Configurações globais e infraestrutura do motor:
     * `src/settings/display.rs`: Centraliza todas as variáveis de resolução, proporção, canvas retrô, MSAA e filtragem de texturas (Anisotrópico 16x / Linear / Pixelated).
     * `src/settings/diagnostics.rs`: Seleção automática multiplataforma de GPU/Backend (DX12 no Windows, Vulkan no Linux, Metal no macOS), trava de 60 FPS e telemetria de frame time.
   * `src/scene/`: Elementos de cena e gameplay subdivididos por domínio:
     * `src/scene/player/player.rs`: Física de movimentação (inércia, derrapagem, gravidade, pulo com corte, inclinação em ladeiras) e vida/status do jogador.
     * `src/scene/world/terrain.rs`: Gerenciador de fases e ciclo de vida dos terrenos (`LevelRoot`, `TerrainMesh`, `ChangeLevelEvent`).
     * `src/scene/world/collision.rs`: Sistema determinístico de colisão com triângulos estáticos da malha do cenário (Piso, Parede, Teto), acelerado por grade espacial uniforme XZ.
     * `src/scene/objects/interaction.rs`: Sistema de objetos interativos dinâmicos com hitboxes (Inimigos/Espinhos, Coletáveis/Moedas, Obstáculos Sólidos, Zonas de Gatilho).
     * `src/scene/camera/camera.rs`: Câmera orbital estilo Lakitu (SM64), com rotação suave, zoom e perseguição desacoplada do display.

---

## 3. Problemas e Desafios Solucionados Durante o Setup

### A. Erro de API no Blender (`PointLight.shadow_buffer_bias`)
* **Sintoma:** No Blender 4.2+, ao registrar uma cena no painel do Blenvy, ocorria o erro: `'PointLight' object has no attribute 'shadow_buffer_bias'`.
* **Causa:** O novo motor EEVEE do Blender 4.2 removeu essa propriedade legada de iluminação pontual.
* **Solução:** Remover lâmpadas padrão da cena no Blender; toda a iluminação é gerenciada diretamente no código Rust/Bevy.

### B. Incompatibilidade de Versões do Bevy
* **Sintoma:** Falha de compilação entre `bevy 0.15` e a versão suportada pelo Blenvy.
* **Solução:** O Blenvy atualmente é baseado no ecossistema Bevy `0.14.2`. O projeto foi travado em `bevy = "0.14"` no `Cargo.toml`.

### C. Conflito de Namespace em Glob Imports
* **Sintoma:** Erro `[E0659]: App is ambiguous` ao utilizar `use blenvy::*;`.
* **Solução:** Utilizar importações explícitas: `use blenvy::{BlenvyPlugin, BlueprintInfo};`.

### D. Tela Preta ao Abrir a Janela Inicial
* **Sintoma:** O arquivo `.glb` carregava nos logs mas nada aparecia na tela.
* **Solução:** Adicionar luz ambiente global (`AmbientLight`) e o `SpatialBundle::default()` no carregamento da raiz da fase.

### E. Texturas Borradas e Brilho Especular Plástico (Phong)
* **Sintoma:** Texturas sofriam com filtragem linear e modelos pareciam plásticos com brilho especular.
* **Solução:** Criado o interceptador `enforce_retro_pixel_graphics` que força `ImageFilterMode::Nearest` e materiais com `reflectance = 0.0` e `perceptual_roughness = 1.0`.

### F. Estiramento/Riscas de Textura nas Rampas do Terreno
* **Sintoma:** A textura do piso aparecia esticada nas bordas e ladeiras fora da coordenada UV [0, 1].
* **Causa:** O `ImageSampler::nearest()` do Bevy define `ClampToEdge` por padrão, esticando o último pixel da borda em UVs repetidas. Adicionalmente, o sampler no arquivo glTF exportado pelo Blender continha `wrapS: 33071 (CLAMP_TO_EDGE)`.
* **Solução:** Configurar `ImageAddressMode::Repeat` tanto no código Rust quanto nos samplers de textura dos arquivos `.glb` (`wrapS: 10497`, `wrapT: 10497`).

### G. Renderização Interna Real a 144p vs Tamanho da Janela
* **Sintoma:** Reduzir a resolução no `WindowPlugin` alterava apenas a janela do SO; ao redimensionar ou maximizar, a cena 3D passava a renderizar em alta resolução moderna nativa do monitor.
* **Solução:** Implementação de uma arquitetura de **Render-to-Texture (Canvas Offscreen)**. O mundo 3D é renderizado estritamente em uma textura de `256 × 144`, e um sprite 2D com projeção ortográfica escala essa textura com Nearest-Neighbor para preencher a janela do SO, mantendo barras pretas (*letterbox/pillarbox*) quando necessário.

### H. Correção de Tela Preta na Câmera 2D Externa (Near Plane Clipping)
* **Sintoma:** Ao adicionar a câmera 2D e o canvas, a janela abria mas ficava 100% preta.
* **Causa:** Ao instanciar `Camera2dBundle` sobrescrevendo `projection: OrthographicProjection { scale, ..default() }`, o valor de `near` padrão de `OrthographicProjection::default()` é `0.0`. No Bevy, isso corta qualquer objeto situado exatamente no plano de tela $Z = 0.0$.
* **Solução:** Inicializar a partir de `Camera2dBundle::default()` (que define `near: -1000.0` e `far: 1000.0`) e alterar somente o campo `scale`.

### I. Centralização e Desacoplamento no Módulo `src/display.rs`
* **Sintoma:** Variáveis de vídeo, resolução e shaders estavam espalhadas entre `camera.rs` e `main.rs`.
* **Solução:** Criação de `src/display.rs`, expondo todas as variáveis e presets no topo do arquivo de forma clara e intuitiva.

### J. Otimização das Consultas de Colisão e Marcação do Terreno
* **Sintoma:** As buscas de piso, teto e paredes percorriam listas completas de triângulos em cada atualização do jogador; a hierarquia do terreno também era percorrida continuamente.
* **Solução em `src/collision.rs`:** Construção de uma grade espacial uniforme 2D no plano XZ, com células de 4 unidades. Piso e teto consultam os triângulos candidatos da célula do ponto; paredes consultam as células cobertas pela AABB do raio, eliminam candidatos repetidos e usam um filtro AABB antes do teste geométrico exato.
* **Geometria extensa:** Triângulos que ocupariam mais de 64 células são mantidos numa lista de fallback e continuam sendo considerados, evitando falsos negativos em superfícies grandes.
* **Construção da colisão:** Os índices das malhas são percorridos diretamente, sem criar uma cópia temporária.
* **`src/terrain.rs`:** A identificação das malhas do terreno só percorre a hierarquia quando aparece uma raiz de fase ou mudam relações pai-filho, em vez de repetir a busca em cada quadro.
* **Validação:** `cargo check` e `cargo test` passaram. Foram adicionados testes para consultas em coordenadas positivas e negativas, deduplicação de candidatos da consulta de paredes e fallback de triângulos grandes.
* **Resultado observado:** A colisão melhorou perceptivelmente, eliminando custos de CPU na busca geométrica.

### K. Diagnóstico e Resolução dos Engasgos no Windows (GPU Híbrida Optimus & Backend DX12)
* **Sintoma:** Micro-stutters e engasgos visuais durante a movimentação da câmera e do jogador no Windows em notebook com GPU híbrida (Intel UHD + NVIDIA RTX 3060 Laptop).
* **Diagnóstico Experimental com Métricas Reais:**
  * **Cenário 1 (GPU Integrada Intel UHD):** O jogo despenca para **31.9 FPS**, tempo de quadro médio de **31.2ms** e picos de travamento de até **118.58ms** (> 33 spikes de stutter por segundo!). Ficou provado que, se o Windows alocar o processo na GPU integrada (por exemplo, no perfil de economia de bateria), o jogo engasga criticamente.
  * **Cenário 2 (Renderização por Software via CPU WARP / DX12):** O rasterizador por software funciona, porém roda entre **4 e 36 FPS** com tempos de quadro de **27ms a 217ms**, confirmando que a pipeline PBR do Bevy exige aceleração gráfica dedicada.
  * **Cenário 3 (RTX 3060 Laptop com Vulkan):** A GPU gera folgadamente entre **190 e 730 FPS**, porém a sincronização com o compositor do Windows (DWM) em notebooks Optimus sofre com dessincronização de frame pacing, gerando sensação de stutter/judder visual na tela de 120Hz.
  * **Cenário 4 (RTX 3060 Laptop com DirectX 12):** O DX12 ativa o modelo Flip nativo (`DXGI_SWAP_EFFECT_FLIP_DISCARD`), sincronizando os frames cravados na taxa do display físico (**118.2 FPS consistentes, 8.46ms de frame time e ZERO spikes de stutter**).
* **Solução Implementada:**
  * Módulo `src/diagnostics.rs` integrado com monitoramento ao vivo de frame time, FPS, 1% Low, desvio padrão/jitter e spikes > 25ms, exibidos tanto no console quanto no título da janela.
  * Configurações centralizadas em `src/display.rs` definindo `GPU_MODE_PREFERENCE = "high"` (força a GPU dedicada) e `RENDER_BACKEND_PREFERENCE = "auto"`.
  * **Seleção Condicional Multiplataforma (`#[cfg(target_os)]`):** No modo `"auto"`, o código detecta em tempo de compilação o sistema operacional de destino e seleciona a API gráfica nativa ideal:
    * **Windows:** DirectX 12 (Flip Model DWM a 120Hz/144Hz sem micro-stutter em notebooks Optimus).
    * **Linux:** Vulkan (API nativa de alta performance).
    * **macOS:** Metal (API nativa da Apple).
  * Suporte nativo a variáveis de ambiente para testes A/B futuros (`$env:GPU_MODE="software"`, `$env:GPU_MODE="integrated"`, `$env:RENDER_BACKEND="vulkan"`, `$env:VSYNC="off"`).
  * **Trava de Taxa de Quadros (TargetFps a 60 FPS):** Implementado limitador de frame rate de precisão com sleep calibrado e spin-wait (`TARGET_FPS = Some(60.0)` em `src/display.rs`), cravando exatamente em **60.0 FPS / 16.66ms** para reproduzir a cadência estável e autêntica de consoles de videogame, além de poupar energia/temperatura na GPU. Pode ser desligado ou customizado via `$env:TARGET_FPS="none"` ou no código.
  * **Anti-Aliasing Refinado de Textura e Geometria:**
    * **Bordas Poligonais:** `DISABLE_MSAA = false` ativa o **4x MSAA** nas silhuetas geométricas.
    * **Textura do Chão e Terreno:** Implementado `TextureFilteringMode::Anisotropic16x` com amostragem linear e **Filtragem Anisotrópica de 16 amostras** (`anisotropy_clamp: 16`), eliminando a cintilação (*shimmering*) e o serrilhado em perspectiva inclinada.
    * **Pós-processamento FXAA:** Suporte opcional a `ENABLE_FXAA` na câmera 3D.
    * Permite alternar via código ou terminal (`$env:TEXTURE_FILTERING="pixelated"` para voltar ao modo Nintendo DS com pixels definidos).

---

## 4. Estrutura e Código dos Módulos do Projeto

### `Cargo.toml`
```toml
[package]
name = "retro_platformer"
version = "0.1.0"
edition = "2021"

[dependencies]
bevy = "0.14"
blenvy = { git = "https://github.com/kaosat-dev/Blenvy" }
```

---

### `src/display.rs` (Central de Vídeo, Resolução e Canvas Retrô)
> **Como alterar resolução:** Basta alterar `INTERNAL_WIDTH` e `INTERNAL_HEIGHT` no topo deste arquivo!

```rust
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
// • 144p Widescreen (Padrão Atual 16:9): INTERNAL_WIDTH = 256,  INTERNAL_HEIGHT = 144
// • Nintendo DS Nativo (4:3):            INTERNAL_WIDTH = 256,  INTERNAL_HEIGHT = 192
// • PS1 / Nintendo 64 (4:3):             INTERNAL_WIDTH = 320,  INTERNAL_HEIGHT = 240
// • 240p Widescreen Retrô:               INTERNAL_WIDTH = 426,  INTERNAL_HEIGHT = 240
// • 360p Retrô Leve:                     INTERNAL_WIDTH = 640,  INTERNAL_HEIGHT = 360
// • 480p SD Retrô:                       INTERNAL_WIDTH = 854,  INTERNAL_HEIGHT = 480
// • 720p HD (Sem Pixelation):            INTERNAL_WIDTH = 1280, INTERNAL_HEIGHT = 720
// • 1080p Full HD Nativo:                INTERNAL_WIDTH = 1920, INTERNAL_HEIGHT = 1080
// =========================================================================

/// 📺 Resolução interna da renderização 3D (Largura em pixels)
pub const INTERNAL_WIDTH: u32 = 256;

/// 📺 Resolução interna da renderização 3D (Altura em pixels)
pub const INTERNAL_HEIGHT: u32 = 144;

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

/// 👾 Desativar Anti-Aliasing (MSAA):
/// true  = Bordas poligonais nítidas e pixeladas autênticas dos consoles retrô
/// false = Bordas suavizadas modernas
pub const DISABLE_MSAA: bool = true;

/// 🕹️ Forçar filtragem Nearest-Neighbor nas texturas (pixel art nítido sem borrão)
pub const FORCE_NEAREST_TEXTURES: bool = true;

/// 🎨 Forçar sombreamento cartunesco difuso (remove reflexos especulares plásticos Phong)
pub const REMOVE_SPECULAR_PHONG: bool = true;

// =========================================================================
// 🎨 CAMADAS DE RENDERIZAÇÃO (RENDER LAYERS)
// =========================================================================

pub const PIXEL_PERFECT_LAYER: RenderLayers = RenderLayers::layer(0);
pub const CANVAS_LAYER: RenderLayers = RenderLayers::layer(1);

// =========================================================================
// 📦 COMPONENTES E RECURSOS DO DISPLAY
// =========================================================================

#[derive(Resource, Clone)]
pub struct RetroCanvasTarget(pub Handle<Image>);

#[derive(Component)]
pub struct CanvasSprite;

#[derive(Component)]
pub struct OuterCamera;

pub struct DisplayPlugin;

impl Plugin for DisplayPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Update, fit_canvas);

        if FORCE_NEAREST_TEXTURES || REMOVE_SPECULAR_PHONG {
            app.add_systems(Update, enforce_retro_pixel_graphics);
        }
    }
}

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
    commands.insert_resource(RetroCanvasTarget(image_handle.clone()));

    commands.spawn((
        SpriteBundle {
            texture: image_handle,
            transform: Transform::from_xyz(0.0, 0.0, 0.0),
            ..default()
        },
        CanvasSprite,
        CANVAS_LAYER,
    ));

    let initial_scale = if let Ok(window) = windows.get_single() {
        let h_scale = window.width() / INTERNAL_WIDTH as f32;
        let v_scale = window.height() / INTERNAL_HEIGHT as f32;
        h_scale.min(v_scale).max(0.1)
    } else {
        1.0
    };

    let mut outer_camera = Camera2dBundle::default();
    outer_camera.camera.order = 1;
    outer_camera.camera.clear_color = ClearColorConfig::Custom(LETTERBOX_COLOR);
    outer_camera.projection.scale = 1.0 / initial_scale;

    commands.spawn((
        outer_camera,
        OuterCamera,
        CANVAS_LAYER,
    ));
}

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
    }
}

pub fn enforce_retro_pixel_graphics(
    mut image_events: EventReader<AssetEvent<Image>>,
    mut images: ResMut<Assets<Image>>,
    mut material_events: EventReader<AssetEvent<StandardMaterial>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    if FORCE_NEAREST_TEXTURES {
        for event in image_events.read() {
            if let AssetEvent::Added { id } | AssetEvent::LoadedWithDependencies { id } | AssetEvent::Modified { id } = event {
                if let Some(image) = images.get(*id) {
                    if image.texture_descriptor.label == Some("retro_canvas") {
                        continue;
                    }

                    let needs_update = match &image.sampler {
                        ImageSampler::Descriptor(desc) => {
                            !matches!(desc.mag_filter, ImageFilterMode::Nearest)
                                || !matches!(desc.min_filter, ImageFilterMode::Nearest)
                                || matches!(desc.address_mode_u, ImageAddressMode::ClampToEdge)
                                || matches!(desc.address_mode_v, ImageAddressMode::ClampToEdge)
                        }
                        _ => true,
                    };

                    if needs_update {
                        if let Some(image_mut) = images.get_mut(*id) {
                            match &mut image_mut.sampler {
                                ImageSampler::Descriptor(desc) => {
                                    desc.mag_filter = ImageFilterMode::Nearest;
                                    desc.min_filter = ImageFilterMode::Nearest;
                                    desc.mipmap_filter = ImageFilterMode::Nearest;
                                    desc.address_mode_u = ImageAddressMode::Repeat;
                                    desc.address_mode_v = ImageAddressMode::Repeat;
                                    desc.address_mode_w = ImageAddressMode::Repeat;
                                }
                                ImageSampler::Default => {
                                    image_mut.sampler = ImageSampler::Descriptor(ImageSamplerDescriptor {
                                        mag_filter: ImageFilterMode::Nearest,
                                        min_filter: ImageFilterMode::Nearest,
                                        mipmap_filter: ImageFilterMode::Nearest,
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
```

---

### `src/camera.rs` (Câmera Orbital Estilo Lakitu)
```rust
use bevy::input::mouse::{MouseMotion, MouseWheel};
use bevy::prelude::*;
use bevy::render::camera::RenderTarget;
use crate::display::{RetroCanvasTarget, PIXEL_PERFECT_LAYER, SKY_COLOR};
use crate::player::Player;

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
            pitch: 0.22,
            follow_speed: 6.0,
            rotation_speed: 2.4,
            mouse_sensitivity: 0.004,
            current_focus: Vec3::ZERO,
        }
    }
}

pub struct LakituCameraPlugin;

impl Plugin for LakituCameraPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(PostUpdate, lakitu_camera_system);
    }
}

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

    commands.spawn((
        Camera3dBundle {
            camera: Camera {
                order: -1,
                target: RenderTarget::Image(canvas_target.0.clone()),
                clear_color: ClearColorConfig::Custom(SKY_COLOR),
                ..default()
            },
            transform: Transform::from_translation(eye).looking_at(Vec3::ZERO, Vec3::Y),
            ..default()
        },
        default_cam,
        PIXEL_PERFECT_LAYER,
    ));
}

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

    // Rotação manual: Q/E ou Setas Esquerda/Direita
    if keyboard_input.pressed(KeyCode::KeyQ) || keyboard_input.pressed(KeyCode::ArrowLeft) {
        camera.yaw += camera.rotation_speed * dt;
    }
    if keyboard_input.pressed(KeyCode::KeyE) || keyboard_input.pressed(KeyCode::ArrowRight) {
        camera.yaw -= camera.rotation_speed * dt;
    }

    // Botão R: Recentraliza a visão instantaneamente atrás do personagem (SM64)
    if keyboard_input.just_pressed(KeyCode::KeyR) {
        let facing = player_transform.rotation * Vec3::Y;
        let target_yaw = (-facing.x).atan2(-facing.z);
        camera.yaw = target_yaw;
    }

    // Controle com botão direito do mouse
    if mouse_button.pressed(MouseButton::Right) {
        for ev in mouse_motion_events.read() {
            camera.yaw -= ev.delta.x * camera.mouse_sensitivity;
            camera.pitch = (camera.pitch + ev.delta.y * camera.mouse_sensitivity)
                .clamp(-0.05, 1.1);
        }
    } else {
        mouse_motion_events.clear();
    }

    // Zoom via Scroll Wheel
    for ev in mouse_wheel_events.read() {
        camera.distance = (camera.distance - ev.y * 1.2).clamp(6.0, 30.0);
    }

    // Suavização do foco de perseguição
    let target_focus = player_transform.translation + Vec3::Y * camera.focus_offset_y;
    let focus_t = (camera.follow_speed * dt).clamp(0.0, 1.0);
    camera.current_focus = camera.current_focus.lerp(target_focus, focus_t);

    let horizontal_dist = camera.distance * camera.pitch.cos();
    let offset = Vec3::new(
        horizontal_dist * camera.yaw.sin(),
        camera.height + camera.distance * camera.pitch.sin(),
        horizontal_dist * camera.yaw.cos(),
    );
    let desired_pos = camera.current_focus + offset;

    camera_transform.translation = camera_transform.translation.lerp(desired_pos, focus_t);
    camera_transform.look_at(camera.current_focus, Vec3::Y);
}
```

---

### `src/player.rs` (Física, Movimentação e Estatísticas)
* **Física Horizontal:** Inércia com aceleração progressiva, curvas suaves, detecção de derrapagem (*skid*) em inversões bruscas e atrito ao soltar os controles.
* **Gravidade e Salto:** Pulo com corte ao soltar a tecla espaço antecipadamente, gravidade contínua e controle aéreo.
* **Inclinação Natural em Ladeiras (`tilt`):** Quando o personagem sobe ou desce rampas, seu eixo sofre uma inclinação sutil na direção da subida, limitada a um limiar superior (`max_tilt_angle: 0.28 rad / ~16°`) e sem inclinar se estiver transversal à rampa.
* **Saúde e Itens:** Sistema de vida com 8 fatias estilo SM64 (`PlayerStats`), contador de moedas, e piscar com invulnerabilidade temporária ao sofrer dano.

---

### `src/collision.rs` (Física Estática Determinística estilo SM64)
* Mantém o recurso `LevelCollision` com triângulos em espaço de mundo classificados pela normal e uma grade espacial uniforme XZ para restringir candidatos:
  * Piso (`normal.y > 0.5`): Consulta triângulos da célula XZ do jogador; mantém o teste baricêntrico vertical, degrau máximo de subida (`STEP_HEIGHT = 0.5`) e *snap* ao descer.
  * Parede (`|normal.y| <= 0.5`): Consulta células cobertas pela AABB do raio, remove candidatos duplicados, filtra por AABB do triângulo e mantém o teste preciso de ponto mais próximo para empurrar horizontalmente.
  * Teto (`normal.y < -0.5`): Consulta triângulos da célula XZ do jogador e mantém o cancelamento da subida ao bater a cabeça.
* Triângulos que cobrem mais de 64 células são mantidos num fallback global; os índices espaciais são reconstruídos ao montar a colisão do nível, não durante cada busca.

---

### `src/terrain.rs` (Ciclo de Vida das Fases)
* Gerencia o carregamento de fases com `LevelRoot`, `TerrainMesh` e troca via `ChangeLevelEvent`.

---

### `src/interaction.rs` (Objetos Interativos Dinâmicos)
* Tipos de resposta: `Hazard` (dano/knockback), `Collectible` (moedas/vida), `SolidObstacle` (empurrar), `TriggerZone` (portais/gatilhos).

---

### `src/main.rs` (Ponto de Entrada e Orquestração)
```rust
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

    // Luz ambiente que clareia as sombras sem criar áreas pretas
    app.insert_resource(AmbientLight {
        color: Color::WHITE,
        brightness: 2200.0,
    });

    // Desativação opcional de MSAA configurada em display.rs
    if DISABLE_MSAA {
        app.insert_resource(Msaa::Off);
    }

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
    .add_plugins(DisplayPlugin)
    .add_plugins(TerrainPlugin)
    .add_plugins(CollisionPlugin)
    .add_plugins(InteractionPlugin)
    .add_plugins(LakituCameraPlugin)
    .add_plugins(PlayerPlugin)
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
```

---

## 5. Status dos Objetivos e Próximos Passos

1. **[CONCLUÍDO] Física de Movimentação Horizontal e Inércia (Passo 1):**
   * Aceleração progressiva, atrito gradual no piso, derrapagem rápida (*skid*) em inversões bruscas.
2. **[CONCLUÍDO] Gravidade, Pulo Variável e Estado de Chão (Passo 2):**
   * Pulo com corte antecipado de subida ao soltar a barra de espaço, controle aéreo moderado.
3. **[CONCLUÍDO] Câmera Seguidora Estilo Lakitu (Passo 3):**
   * Câmera orbital suavizada em `PostUpdate`, controles manuais via `Q`/`E`, recentralização instantânea com `R`, rotação pelo botão direito e zoom pelo scroll.
4. **[CONCLUÍDO] Colisão Determinística Estática com Terreno (Passo 4):**
   * Detecção de piso baricêntrico em espaço de mundo, colisão esférica com paredes e cancelamento em tetos.
   * Alinhamento sutil do corpo do jogador à normal do terreno em subidas e descidas (`tilt`), com limiar superior angular.
    * Otimização das consultas com grade espacial XZ, filtro AABB para paredes, acesso direto aos índices da malha e marcação do terreno acionada por alterações na hierarquia. Testes unitários da grade e compilação passaram.
5. **[CONCLUÍDO] Refatoração Modular para Múltiplas Fases e Objetos:**
   * Separação de terrenos (`terrain.rs`), objetos interativos (`interaction.rs`), colisão de terreno isolada (`collision.rs`) e dados do jogador (`player.rs`).
6. **[CONCLUÍDO] Estética Nintendo DS & Renderização Interna 144p:**
   * Texturas Nearest com repetição (Tiling), materiais difusos sem reflexo Phong, sem MSAA.
   * Renderização 3D offscreen travada estritamente na resolução configurada em `src/display.rs` com redimensionamento dinâmico e preservação de aspect ratio.
7. **[CONCLUÍDO] Investigação e Diagnóstico Definitivo dos Engasgos no Windows:**
   * Implementado o módulo `src/diagnostics.rs` com métricas em tempo real (FPS, frame time, 1% low, jitter e contador de spikes) e identificação do adaptador físico WGPU.
   * **Testes A/B Realizados:**
     * *GPU Integrada (Intel UHD):* Gargalo crítico a **31.9 FPS**, 31.2ms médios e travamentos de até **118.58ms** (>33 spikes/s).
     * *Software Rendering (WARP DX12):* Roda a **4-36 FPS** com tempos de até 217ms, provando a necessidade de aceleração por GPU dedicada.
     * *RTX 3060 Laptop (Vulkan):* Gera 190-730 FPS, mas com dessincronização em relação à taxa nativa de 120Hz do display em laptops Optimus.
     * *RTX 3060 Laptop (DirectX 12):* Sincronização impecável com o DWM via DXGI Flip Model, cravando **118.2 FPS consistentes, 8.46ms de frame time e ZERO spikes**.
   * **Resolução:** Configurado `GPU_MODE_PREFERENCE = "high"` e `RENDER_BACKEND_PREFERENCE = "dx12"` em `src/display.rs`, com fallback para variáveis de ambiente.
8. **[PRÓXIMO CAPÍTULO] Modelo Final e Animações:**
   * Modelagem/importação da malha 3D final do personagem no Blender com esqueleto e animações (andar, correr, pular, derrapar, ficar parado).
   * Integração do mixer de animações do Bevy para transições fluidas baseadas na velocidade do `PlayerController`.
   * Criação de novos cenários no Blender e posicionamento de moedas/inimigos usando a arquitetura de `interaction.rs`.
