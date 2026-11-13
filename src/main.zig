const std = @import("std");
const builtin = @import("builtin");
const rl = @import("rl.zig");
pub const math = @import("math.zig");
pub const settings = @import("settings/mod.zig");
pub const scene = @import("scene/mod.zig");

const display = settings.display;
const diagnostics = settings.diagnostics;
const LakituCamera = scene.camera.LakituCamera;
const Player = scene.player.Player;
const LevelCollision = scene.world.collision.LevelCollision;
const terrain_mod = scene.world.terrain;
const TerrainManager = terrain_mod.TerrainManager;
const InteractionWorld = scene.objects.interaction.InteractionWorld;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    // 🛠️ 1. Carrega configurações de GPU, VSync e FPS Cap (diagnostics.zig & display.zig)
    const diag_config = diagnostics.DiagnosticRenderConfig.loadConfiguration();
    diag_config.applyWindowFlags();

    // 📺 2. Inicializa a janela e contexto gráfico OpenGL 3.3
    rl.c.InitWindow(display.WINDOW_WIDTH, display.WINDOW_HEIGHT, display.WINDOW_TITLE.ptr);
    defer rl.c.CloseWindow();

    // 🎨 3. Inicializa o sistema de Display Offscreen (Canvas Retrô, Shaders de Luz DS e FXAA)
    var display_sys = display.DisplaySystem.init();
    defer display_sys.deinit();

    // ⏱️ 4. Inicializa telemetria de frame pacing e limitador de FPS de alta precisão
    var diagnostics_sys = diagnostics.DiagnosticsSystem.init(allocator, diag_config);
    defer diagnostics_sys.deinit();
    diagnostics_sys.logHardwareInfoOnce();

    // 🧱 5. Inicializa sistema de colisão determinística (Grade Espacial XZ) e carrega o terreno GLB
    var collision = LevelCollision.init(allocator);
    defer collision.deinit();

    var terrain = TerrainManager.init();
    defer terrain.deinit();
    try terrain.loadLevel(terrain_mod.DEFAULT_LEVEL_PATH, &display_sys, &collision);

    // 💥 6. Inicializa o mundo de objetos interativos (Inimigos, Moedas, Obstáculos, Triggers)
    var interactions = InteractionWorld.init(allocator);
    defer interactions.deinit();

    // 🎥 7. Inicializa a Câmera Orbital estilo Lakitu (Super Mario 64)
    var camera = LakituCamera.init();

    // 🏃 8. Instancia o Jogador (Cone vermelho com física de inércia, pulo variável e tilt)
    var player = Player.init(&display_sys);
    defer player.deinit();

    // Zera o cronômetro de frame após o carregamento inicial de disco/GPU
    diagnostics_sys.resetTimerAfterLoading();

    // 🔄 Loop Principal do Jogo
    while (!rl.c.WindowShouldClose()) {
        const dt = diagnostics_sys.current_dt;

        // 🎛️ Sistema de atalhos no teclado para alterar opções de display em tempo real:
        // [F1] Alternar exibição do OSD (HUD de informações)
        if (rl.c.IsKeyPressed(rl.c.KEY_F1)) {
            const shown = display_sys.toggleOverlay();
            std.log.info("📊 OSD Overlay: {s}", .{if (shown) "ATIVADO" else "OCULTO"});
        }

        // [F2] Ciclar modo de filtragem de texturas (CrispPixelAA -> Pixelated -> Linear -> Anisotropic16x)
        if (rl.c.IsKeyPressed(rl.c.KEY_F2)) {
            const new_mode = display_sys.cycleTextureFiltering();
            terrain.updateTextureFiltering(new_mode, display_sys.crisp_fallback);
            std.log.info("🎨 Filtragem de Texturas alterada para: {s}", .{@tagName(new_mode)});
        }

        // [F3] Alternar escalonamento do canvas na janela (Nearest <-> Bilinear)
        if (rl.c.IsKeyPressed(rl.c.KEY_F3)) {
            const new_scale = display_sys.toggleCanvasScaling();
            std.log.info("🖼️ Escalonamento do Canvas alterado para: {s}", .{@tagName(new_scale)});
        }

        // [F4] Alternar pós-processamento FXAA (ON <-> OFF)
        if (rl.c.IsKeyPressed(rl.c.KEY_F4)) {
            const fxaa_on = display_sys.toggleFxaa();
            std.log.info("✨ FXAA: {s}", .{if (fxaa_on) "LIGADO" else "DESLIGADO"});
        }

        // [F5] Alternar limitador de FPS (60 FPS cravados <-> Livre / Destravado)
        if (rl.c.IsKeyPressed(rl.c.KEY_F5)) {
            const new_cap = diagnostics_sys.toggleTargetFps();
            if (new_cap) |cap| {
                std.log.info("🎯 Limite de FPS: {d:.0} FPS cravados", .{cap});
            } else {
                std.log.info("🎯 Limite de FPS: Destravado (Livre / Máxima Performance)", .{});
            }
        }

        // [F6/F7] Ajustar threshold Near de Crisp AA (-2 / +2)
        // [F8/F9] Ajustar threshold Far de Crisp AA (-2 / +2)
        if (display_sys.filtering_mode == .CrispPixelAA) {
            var changed = false;
            var near = display_sys.crisp_near_val;
            var far = display_sys.crisp_far_val;

            if (rl.c.IsKeyPressed(rl.c.KEY_F6)) {
                near = @max(0.0, near - 2.0);
                changed = true;
            }
            if (rl.c.IsKeyPressed(rl.c.KEY_F7)) {
                near = @min(far - 0.5, near + 2.0);
                changed = true;
            }
            if (rl.c.IsKeyPressed(rl.c.KEY_F8)) {
                far = @max(near + 0.5, far - 2.0);
                changed = true;
            }
            if (rl.c.IsKeyPressed(rl.c.KEY_F9)) {
                far = far + 2.0;
                changed = true;
            }

            if (changed) {
                display_sys.setCrispThresholds(near, far);
                std.log.info("🎚️ Crisp AA Ajustado: Near = {d:.1}, Far = {d:.1}", .{ near, far });
            }
        }

        // [F10] Alternar filtro de fallback além de Far (Anisotropic16x <-> Linear)
        if (rl.c.IsKeyPressed(rl.c.KEY_F10)) {
            const new_fb = display_sys.toggleCrispFallback();
            if (display_sys.filtering_mode == .CrispPixelAA) {
                terrain.updateTextureFiltering(display_sys.filtering_mode, new_fb);
            }
            std.log.info("🌊 Crisp Fallback alterado para: {s}", .{@tagName(new_fb)});
        }

        // [F11] Alternar MSAA 4x offscreen (ON <-> OFF)
        if (rl.c.IsKeyPressed(rl.c.KEY_F11)) {
            const msaa_on = display_sys.toggleMsaa();
            std.log.info("🔷 MSAA 4x: {s}", .{if (msaa_on) "LIGADO" else "DESLIGADO"});
        }

        // [F12] Alternar entre modo janela e tela cheia
        if (rl.c.IsKeyPressed(rl.c.KEY_F12)) {
            rl.c.ToggleFullscreen();
            std.log.info("🖥️ Modo de exibição: {s}", .{if (rl.c.IsWindowFullscreen()) "TELA CHEIA" else "JANELA"});
        }

        // --- UPDATE ---
        interactions.clearEvents();
        player.updateMovement(dt, &camera, &collision);
        player.updateAnimation(dt);
        interactions.update(&player.position);
        player.updateInteractionsAndStatus(dt, &interactions);

        // --- POST-UPDATE (Câmera Lakitu) ---
        camera.update(dt, player.position, player.rotation);

        // --- RENDER (Passe 1: Mundo 3D no Canvas Offscreen + Passe 2: FXAA & Escala Nearest na Janela) ---
        display_sys.begin3DCanvas(camera.toRaylibCamera());
        {
            terrain.draw();
            player.draw();
        }
        display_sys.end3DCanvasAndPresent(.{
            .gpu_name = diagnostics_sys.gpu_name,
            .fps = diagnostics_sys.current_fps,
            .frametime_ms = diagnostics_sys.current_avg_ms,
            .target_fps = diagnostics_sys.config.target_fps,
            .vsync = diagnostics_sys.config.vsync,
        });

        // --- DIAGNOSTICS & FRAME CAP ---
        _ = diagnostics_sys.endFrameAndMeasure();
    }
}

test {
    _ = @import("scene/world/collision.zig");
}
