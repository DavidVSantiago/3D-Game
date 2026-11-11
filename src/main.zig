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

        // --- UPDATE ---
        interactions.clearEvents();
        player.updateMovement(dt, &camera, &collision);
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
        display_sys.end3DCanvasAndPresent();

        // --- DIAGNOSTICS & FRAME CAP ---
        _ = diagnostics_sys.endFrameAndMeasure();
    }
}

test {
    _ = @import("scene/world/collision.zig");
}
