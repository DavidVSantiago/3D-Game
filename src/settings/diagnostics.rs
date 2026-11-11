use bevy::prelude::*;
use bevy::render::renderer::{initialize_renderer, RenderAdapterInfo, RenderInstance, WgpuWrapper};
use bevy::render::settings::{Backends, PowerPreference, RenderCreation, WgpuSettings};
use bevy::window::{PresentMode, PrimaryWindow};
use crate::settings::display::{ENABLE_VSYNC, GPU_MODE_PREFERENCE, RENDER_BACKEND_PREFERENCE, TARGET_FPS, WINDOW_TITLE};
use std::sync::Arc;
use std::time::{Duration, Instant};

/// 🎯 Recurso global que define o limite de FPS (Frame Cap)
#[derive(Resource, Clone, Copy, Debug)]
pub struct TargetFps(pub Option<f32>);

/// 🛠️ Modos de seleção de GPU para testes A/B
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GpuSelectionMode {
    /// GPU Dedicada de Alta Performance (ex: RTX 3060 Laptop no Windows/Linux, Apple GPU no Mac)
    HighPerformance,
    /// GPU Integrada de Baixo Consumo (ex: Intel UHD Graphics)
    Integrated,
    /// Renderização puramente por Software via CPU (WARP no Windows via DX12)
    SoftwareWARP,
    /// Seleção automática padrão do Bevy/WGPU
    Auto,
}

/// 🛠️ Backend gráfico com seleção multiplataforma
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackendSelection {
    /// Seleção automática inteligente baseada no Sistema Operacional:
    /// • Windows: DirectX 12 (Flip Model nativo a 120Hz/144Hz sem stutter)
    /// • Linux:   Vulkan (API nativa de alta performance)
    /// • macOS:   Metal (API nativa da Apple)
    Auto,
    /// Forçar DirectX 12 (Windows)
    Dx12,
    /// Forçar Vulkan (Windows / Linux)
    Vulkan,
    /// Forçar Metal (macOS)
    Metal,
}

/// 🛠️ Configuração consolidada de diagnósticos e renderização
#[derive(Debug, Clone)]
pub struct DiagnosticRenderConfig {
    pub gpu_mode: GpuSelectionMode,
    pub backend: BackendSelection,
    pub present_mode: PresentMode,
    pub target_fps: Option<f32>,
}

impl DiagnosticRenderConfig {
    /// Lê a configuração a partir de variáveis de ambiente com fallback para display.rs
    pub fn load_configuration() -> Self {
        let env_gpu = std::env::var("GPU_MODE").unwrap_or_else(|_| GPU_MODE_PREFERENCE.to_string());
        let gpu_mode = match env_gpu.to_lowercase().as_str() {
            "integrated" | "low" | "igpu" | "intel" => GpuSelectionMode::Integrated,
            "software" | "cpu" | "warp" => GpuSelectionMode::SoftwareWARP,
            "high" | "discrete" | "dgpu" | "nvidia" | "rtx" => GpuSelectionMode::HighPerformance,
            _ => GpuSelectionMode::Auto,
        };

        let env_backend = std::env::var("RENDER_BACKEND").unwrap_or_else(|_| RENDER_BACKEND_PREFERENCE.to_string());
        let backend = match env_backend.to_lowercase().as_str() {
            "dx12" | "directx" => BackendSelection::Dx12,
            "vulkan" | "vk" => BackendSelection::Vulkan,
            "metal" => BackendSelection::Metal,
            _ => BackendSelection::Auto,
        };

        let env_vsync = std::env::var("VSYNC");
        let present_mode = match env_vsync {
            Ok(v) => match v.to_lowercase().as_str() {
                "off" | "novsync" | "immediate" | "false" | "0" => PresentMode::AutoNoVsync,
                "mailbox" | "fast" => PresentMode::Mailbox,
                _ => PresentMode::Fifo,
            },
            Err(_) => {
                if ENABLE_VSYNC {
                    PresentMode::Fifo
                } else {
                    PresentMode::AutoNoVsync
                }
            }
        };

        let target_fps = if let Ok(val) = std::env::var("TARGET_FPS") {
            match val.to_lowercase().as_str() {
                "none" | "0" | "unlimited" | "off" => None,
                num => num.parse::<f32>().ok().filter(|&fps| fps > 0.0),
            }
        } else {
            TARGET_FPS
        };

        Self {
            gpu_mode,
            backend,
            present_mode,
            target_fps,
        }
    }

    /// Resolve os backends ótimos para o sistema operacional em que o código está sendo compilado
    fn resolve_native_backend(&self) -> Backends {
        match self.backend {
            BackendSelection::Dx12 => Backends::DX12,
            BackendSelection::Vulkan => Backends::VULKAN,
            BackendSelection::Metal => Backends::METAL,
            BackendSelection::Auto => {
                #[cfg(target_os = "linux")]
                {
                    Backends::VULKAN
                }

                #[cfg(target_os = "macos")]
                {
                    Backends::METAL
                }

                #[cfg(target_os = "windows")]
                {
                    Backends::DX12
                }

                #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
                {
                    Backends::PRIMARY
                }
            }
        }
    }

    /// Constrói o `RenderCreation` apropriado para o `RenderPlugin`
    pub fn build_render_creation(&self) -> RenderCreation {
        let selected_backend = self.resolve_native_backend();

        match self.gpu_mode {
            GpuSelectionMode::SoftwareWARP => {
                info!("🛠️ [CONFIG] Forçando renderização por Software (WARP via DX12 / CPU)...");
                let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
                    backends: wgpu::Backends::DX12,
                    ..default()
                });

                let settings = WgpuSettings {
                    backends: Some(Backends::DX12),
                    power_preference: PowerPreference::None,
                    ..default()
                };

                let request_options = wgpu::RequestAdapterOptions {
                    power_preference: wgpu::PowerPreference::None,
                    force_fallback_adapter: true,
                    compatible_surface: None,
                };

                let (device, queue, adapter_info, render_adapter) =
                    bevy::tasks::block_on(initialize_renderer(&instance, &settings, &request_options));

                RenderCreation::Manual(
                    device,
                    queue,
                    adapter_info,
                    render_adapter,
                    RenderInstance(Arc::new(WgpuWrapper::new(instance))),
                )
            }
            GpuSelectionMode::Integrated => {
                info!("🛠️ [CONFIG] Forçando GPU Integrada (LowPower: Intel UHD Graphics)...");
                RenderCreation::Automatic(WgpuSettings {
                    backends: Some(selected_backend),
                    power_preference: PowerPreference::LowPower,
                    ..default()
                })
            }
            GpuSelectionMode::HighPerformance => {
                info!(
                    "🛠️ [CONFIG] Modo Multiplataforma: GPU Alta Performance (Backend: {:?})...",
                    selected_backend
                );
                RenderCreation::Automatic(WgpuSettings {
                    backends: Some(selected_backend),
                    power_preference: PowerPreference::HighPerformance,
                    ..default()
                })
            }
            GpuSelectionMode::Auto => {
                info!(
                    "🛠️ [CONFIG] Modo Automático Multiplataforma (Backend: {:?})...",
                    selected_backend
                );
                RenderCreation::Automatic(WgpuSettings {
                    backends: Some(selected_backend),
                    power_preference: PowerPreference::HighPerformance,
                    ..default()
                })
            }
        }
    }
}

pub struct DiagnosticsPlugin;

impl Plugin for DiagnosticsPlugin {
    fn build(&self, app: &mut App) {
        let diag_config = DiagnosticRenderConfig::load_configuration();
        app.insert_resource(TargetFps(diag_config.target_fps))
            .add_systems(Update, (log_hardware_info_once, frame_pacing_monitor))
            .add_systems(Last, frame_rate_limiter);
    }
}

/// 🎯 Limitador de taxa de quadros (FPS Cap) de alta precisão
fn frame_rate_limiter(
    target_fps: Res<TargetFps>,
    mut last_frame: Local<Option<Instant>>,
) {
    let Some(fps) = target_fps.0 else { return; };
    if fps <= 0.0 { return; }
    let target_duration = Duration::from_secs_f64(1.0 / fps as f64);

    if let Some(prev) = *last_frame {
        let elapsed = prev.elapsed();
        if elapsed < target_duration {
            let sleep_needed = target_duration - elapsed;
            // No Windows, thread::sleep tem granularidade de ~1ms.
            // Dormimos até 1.5ms antes e finalizamos com spin_loop para máxima precisão:
            if sleep_needed > Duration::from_micros(2000) {
                std::thread::sleep(sleep_needed - Duration::from_micros(1500));
            }
            while prev.elapsed() < target_duration {
                std::hint::spin_loop();
            }
        }
    }
    *last_frame = Some(Instant::now());
}

/// 🖥️ Loga com detalhes o dispositivo gráfico, backend e driver assim que o WGPU concluir a inicialização
fn log_hardware_info_once(
    adapter_info: Option<Res<RenderAdapterInfo>>,
    target_fps: Res<TargetFps>,
    mut logged: Local<bool>,
) {
    if *logged {
        return;
    }
    if let Some(info) = adapter_info {
        let cap_info = match target_fps.0 {
            Some(fps) => format!("{:.0} FPS cravados", fps),
            None => "Ilimitado / VSync nativo".to_string(),
        };

        info!("============================================================");
        info!("🎮 [GPU DIAGNOSTICS] Adaptador Ativo do WGPU:");
        info!("   • Dispositivo:      {}", info.name);
        info!("   • Backend Gráfico:  {:?}", info.backend);
        info!("   • Tipo de GPU:      {:?}", info.device_type);
        info!("   • Limite de FPS:    {}", cap_info);
        info!("   • Versão Driver:    {}", info.driver);
        info!("   • Info Adicional:   {}", info.driver_info);
        info!("============================================================");
        *logged = true;
    }
}

/// ⏱️ Estrutura que acumula métricas de cada quadro renderizado
#[derive(Default)]
struct FramePacingStats {
    frame_times_ms: Vec<f32>,
    last_log_seconds: f32,
    stutters_count: u32,
    total_frames: u64,
}

/// 📊 Monitor em tempo real de consistência de frame pacing, spikes de stutter e desvio padrão
fn frame_pacing_monitor(
    time: Res<Time>,
    mut stats: Local<FramePacingStats>,
    mut windows: Query<&mut Window, With<PrimaryWindow>>,
    adapter_info: Option<Res<RenderAdapterInfo>>,
    target_fps: Res<TargetFps>,
) {
    let dt = time.delta_seconds();
    let dt_ms = dt * 1000.0;
    stats.frame_times_ms.push(dt_ms);
    stats.total_frames += 1;

    // Detecta picos de latência (engasgo):
    // Se estiver travado em 60 FPS (16.66ms/frame), qualquer frame > 22.0ms é um spike perceptível.
    // Se estiver livre (ex: 120Hz = 8.3ms), limite é 14.0ms.
    let spike_threshold = match target_fps.0 {
        Some(target) if target <= 60.0 => (1000.0 / target) * 1.35,
        _ => 22.0,
    };

    if dt_ms > spike_threshold {
        stats.stutters_count += 1;
    }

    let elapsed = time.elapsed_seconds();
    // Exibe estatísticas consolidadas no console a cada 1 segundo
    if elapsed - stats.last_log_seconds >= 1.0 && !stats.frame_times_ms.is_empty() {
        let count = stats.frame_times_ms.len();
        let avg_ms = stats.frame_times_ms.iter().sum::<f32>() / count as f32;
        let fps = 1000.0 / avg_ms;

        let mut sorted = stats.frame_times_ms.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let min_ms = sorted.first().copied().unwrap_or(0.0);
        let max_ms = sorted.last().copied().unwrap_or(0.0);

        // 1% Low frame time (o 99º percentil dos piores tempos de quadro)
        let idx_99 = ((count as f32 * 0.99).floor() as usize).min(count - 1);
        let p99_ms = sorted[idx_99];
        let low_1_percent_fps = 1000.0 / p99_ms;

        // Desvio padrão (Jitter em ms: quanto menor, mais estável e suave)
        let variance = stats.frame_times_ms.iter().map(|t| (t - avg_ms).powi(2)).sum::<f32>() / count as f32;
        let std_dev_ms = variance.sqrt();

        let gpu_short_name = adapter_info
            .as_ref()
            .map(|a| a.name.clone())
            .unwrap_or_else(|| "GPU".into());

        let target_str = match target_fps.0 {
            Some(t) => format!(" (Alvo: {:.0})", t),
            None => "".to_string(),
        };

        // Atualiza a barra de título da janela com estatísticas ao vivo
        if let Ok(mut win) = windows.get_single_mut() {
            win.title = format!(
                "{} | {} | {:.0} FPS{} ({:.1}ms) | 1% Low: {:.0} FPS | Spikes: {}",
                WINDOW_TITLE, gpu_short_name, fps, target_str, avg_ms, low_1_percent_fps, stats.stutters_count
            );
        }

        info!(
            "⏱️ [PERF] FPS: {:5.1}{} (Méd: {:4.2}ms) | 1% Low: {:5.1} FPS ({:4.2}ms) | Min/Máx: {:4.2}/{:4.2}ms | Jitter(σ): {:4.2}ms | Spikes: {}",
            fps, target_str, avg_ms, low_1_percent_fps, p99_ms, min_ms, max_ms, std_dev_ms, stats.stutters_count
        );

        stats.frame_times_ms.clear();
        stats.stutters_count = 0;
        stats.last_log_seconds = elapsed;
    }
}
