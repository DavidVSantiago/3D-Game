const std = @import("std");
const rl = @import("../rl.zig");
const math = @import("../math.zig");
const Vec2 = math.Vec2;

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
pub const INTERNAL_WIDTH: i32 = 854;

/// 📺 Resolução interna da renderização 3D (Altura em pixels)
pub const INTERNAL_HEIGHT: i32 = 480;

/// 🪟 Resolução inicial da janela no monitor (pode redimensionar livremente)
pub const WINDOW_WIDTH: i32 = 1280;
pub const WINDOW_HEIGHT: i32 = 720;

/// 🏷️ Título da janela do jogo
pub const WINDOW_TITLE: [:0]const u8 = "Retro 3D Platformer (DS Style)";

/// 🔲 Permitir que a janela seja redimensionada pelo usuário
pub const WINDOW_RESIZABLE: bool = true;

/// ☀️ Cor de fundo do céu na renderização 3D (estilo céu vibrante do Nintendo DS: srgb(0.45, 0.75, 0.98))
pub const SKY_COLOR = rl.c.Color{ .r = 115, .g = 191, .b = 250, .a = 255 };

/// ⬛ Cor das bordas letterbox / pillarbox fora do aspect ratio (quando redimensiona)
pub const LETTERBOX_COLOR = rl.c.BLACK;

/// 👾 Desativar Anti-Aliasing Geométrico (MSAA):
/// true  = Bordas poligonais nítidas e pixeladas autênticas dos consoles retrô
/// false = Bordas suavizadas modernas (4x MSAA)
pub const DISABLE_MSAA: bool = false;

/// 🎨 Modo de Filtragem das Texturas (Anti-Aliasing do Chão, Terreno e Objetos):
pub const TextureFilteringMode = enum {
    /// 👾 Nearest-Neighbor: Pixels nítidos e quadrados (estilo Nintendo DS autêntico)
    Pixelated,
    /// 🌊 Linear: Interpolação bilinear/trilinear suave básica
    Linear,
    /// 💎 Anisotrópico 16x: Filtragem anisotrópica máxima (chão perfeitamente suave em ângulo rasante sem cintilação)
    Anisotropic16x,
};

/// 🎨 Filtragem ativa das texturas:
/// Alterne entre .Anisotropic16x (chão suave e nítido) ou .Pixelated (retrô pixel art)
/// 💡 Também pode ser sobrescrito via terminal: $env:TEXTURE_FILTERING="anisotropic" ou "pixelated"
pub const TEXTURE_FILTERING: TextureFilteringMode = .Pixelated;

/// ✨ Anti-Aliasing de Pós-Processamento (FXAA) na Câmera 3D:
/// • true  = Suaviza a cena 3D inteira (arestas + interior de texturas) na resolução interna
/// • false = Desativado
pub const ENABLE_FXAA: bool = true;

/// 🎨 Forçar sombreamento cartunesco difuso (remove reflexos especulares plásticos Phong)
pub const REMOVE_SPECULAR_PHONG: bool = true;

// =========================================================================
// 🚀 PREFERÊNCIAS DE GPU, DRIVER E VSYNC
// =========================================================================

/// 🎮 Preferência de GPU:
/// • "high"     = (Recomendado no Windows) Força GPU Dedicada de Alta Performance (NVIDIA RTX 3060 Laptop)
/// • "low"      = GPU Integrada de Baixo Consumo
/// • "software" = Renderização por Software
/// • "auto"     = Automático
pub const GPU_MODE_PREFERENCE: []const u8 = "high";

/// ⚡ Backend gráfico multiplataforma:
pub const RENDER_BACKEND_PREFERENCE: []const u8 = "auto";

/// 🔄 Sincronização Vertical (VSync):
pub const ENABLE_VSYNC: bool = true;

/// 🎯 Limite de Taxa de Quadros (FPS Cap):
/// • 60.0 = Trava em 60 FPS cravados (padrão autêntico e suave de consoles)
/// • null = Taxa livre (acompanha os Hz do monitor, ex: 120Hz, 144Hz)
pub const TARGET_FPS: ?f32 = 60.0;

/// Helper para obter o modo de filtragem de texturas respeitando variáveis de ambiente
pub fn getTextureFilteringMode() TextureFilteringMode {
    const val = rl.getEnv("TEXTURE_FILTERING") orelse return TEXTURE_FILTERING;

    if (std.ascii.eqlIgnoreCase(val, "pixelated") or
        std.ascii.eqlIgnoreCase(val, "nearest") or
        std.ascii.eqlIgnoreCase(val, "retro"))
    {
        return .Pixelated;
    }
    if (std.ascii.eqlIgnoreCase(val, "linear") or
        std.ascii.eqlIgnoreCase(val, "smooth"))
    {
        return .Linear;
    }
    if (std.ascii.eqlIgnoreCase(val, "anisotropic") or
        std.ascii.eqlIgnoreCase(val, "af") or
        std.ascii.eqlIgnoreCase(val, "aniso") or
        std.ascii.eqlIgnoreCase(val, "16x"))
    {
        return .Anisotropic16x;
    }
    return TEXTURE_FILTERING;
}

/// Configura amostragem de uma textura 2D (Pixelated, Linear ou Anisotrópico 16x) mantendo Tiling (Repeat)
pub fn configureModelTexture(texture: *rl.c.Texture2D, mode: TextureFilteringMode) void {
    if (texture.id == 0) return;

    // Garante repetição (Tiling) em U e V para evitar estiramento nas rampas
    rl.c.SetTextureWrap(texture.*, rl.c.TEXTURE_WRAP_REPEAT);

    switch (mode) {
        .Pixelated => {
            rl.c.SetTextureFilter(texture.*, rl.c.TEXTURE_FILTER_POINT);
        },
        .Linear => {
            if (texture.mipmaps <= 1) {
                rl.c.GenTextureMipmaps(texture);
            }
            rl.c.SetTextureFilter(texture.*, rl.c.TEXTURE_FILTER_TRILINEAR);
        },
        .Anisotropic16x => {
            if (texture.mipmaps <= 1) {
                rl.c.GenTextureMipmaps(texture);
            }
            rl.c.SetTextureFilter(texture.*, rl.c.TEXTURE_FILTER_ANISOTROPIC_16X);
        },
    }
}

// =========================================================================
// 🎨 SHADERS GLSL 330 (ILUMINAÇÃO CARTUNESCA DS & PÓS-PROCESSAMENTO FXAA)
// =========================================================================

const LIGHTING_VS: [:0]const u8 =
    \\#version 330
    \\in vec3 vertexPosition;
    \\in vec2 vertexTexCoord;
    \\in vec3 vertexNormal;
    \\in vec4 vertexColor;
    \\uniform mat4 mvp;
    \\uniform mat4 matModel;
    \\uniform mat4 matNormal;
    \\out vec3 fragPosition;
    \\out vec2 fragTexCoord;
    \\out vec4 fragColor;
    \\out vec3 fragNormal;
    \\void main() {
    \\    fragPosition = vec3(matModel * vec4(vertexPosition, 1.0));
    \\    fragTexCoord = vertexTexCoord;
    \\    fragColor = vertexColor;
    \\    fragNormal = normalize(vec3(matNormal * vec4(vertexNormal, 0.0)));
    \\    gl_Position = mvp * vec4(vertexPosition, 1.0);
    \\}
;

const LIGHTING_FS: [:0]const u8 =
    \\#version 330
    \\in vec3 fragPosition;
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\in vec3 fragNormal;
    \\uniform sampler2D texture0;
    \\uniform vec4 colDiffuse;
    \\out vec4 finalColor;
    \\void main() {
    \\    vec4 texelColor = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    \\    vec3 N = normalize(gl_FrontFacing ? fragNormal : -fragNormal);
    \\    // Luz direcional solar em (10, 20, 10) olhando para a origem
    \\    vec3 lightDir = normalize(vec3(10.0, 20.0, 10.0));
    \\    float ndotl = max(dot(N, lightDir), 0.0);
    \\    // Luz ambiente viva (sem sombras pretas) + difusa solar pura (zero Phong/especular)
    \\    float lighting = 0.58 + 0.42 * ndotl;
    \\    finalColor = vec4(texelColor.rgb * lighting, texelColor.a);
    \\}
;

const FXAA_FS: [:0]const u8 =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\uniform sampler2D texture0;
    \\uniform vec2 resolution;
    \\out vec4 finalColor;
    \\void main() {
    \\    vec2 invRes = 1.0 / resolution;
    \\    vec3 rgbNW = texture(texture0, fragTexCoord + vec2(-1.0, -1.0) * invRes).rgb;
    \\    vec3 rgbNE = texture(texture0, fragTexCoord + vec2( 1.0, -1.0) * invRes).rgb;
    \\    vec3 rgbSW = texture(texture0, fragTexCoord + vec2(-1.0,  1.0) * invRes).rgb;
    \\    vec3 rgbSE = texture(texture0, fragTexCoord + vec2( 1.0,  1.0) * invRes).rgb;
    \\    vec4 texColor = texture(texture0, fragTexCoord);
    \\    vec3 rgbM  = texColor.rgb;
    \\    vec3 luma = vec3(0.299, 0.587, 0.114);
    \\    float lumaNW = dot(rgbNW, luma);
    \\    float lumaNE = dot(rgbNE, luma);
    \\    float lumaSW = dot(rgbSW, luma);
    \\    float lumaSE = dot(rgbSE, luma);
    \\    float lumaM  = dot(rgbM,  luma);
    \\    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    \\    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
    \\    vec2 dir;
    \\    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    \\    dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));
    \\    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * (1.0/8.0)), 1.0/128.0);
    \\    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    \\    dir = min(vec2(8.0, 8.0), max(vec2(-8.0, -8.0), dir * rcpDirMin)) * invRes;
    \\    vec3 rgbA = 0.5 * (
    \\        texture(texture0, fragTexCoord + dir * (1.0/3.0 - 0.5)).rgb +
    \\        texture(texture0, fragTexCoord + dir * (2.0/3.0 - 0.5)).rgb);
    \\    vec3 rgbB = rgbA * 0.5 + 0.25 * (
    \\        texture(texture0, fragTexCoord + dir * -0.5).rgb +
    \\        texture(texture0, fragTexCoord + dir *  0.5).rgb);
    \\    float lumaB = dot(rgbB, luma);
    \\    if ((lumaB < lumaMin) || (lumaB > lumaMax)) {
    \\        finalColor = vec4(rgbA, texColor.a) * fragColor;
    \\    } else {
    \\        finalColor = vec4(rgbB, texColor.a) * fragColor;
    \\    }
    \\}
;

// =========================================================================
// 📦 SISTEMA DE DISPLAY E CANVAS RETRÔ OFFSCREEN
// =========================================================================

pub const DisplaySystem = struct {
    /// Textura offscreen onde o mundo 3D é desenhado na resolução interna
    scene_target: rl.c.RenderTexture2D,
    /// Textura offscreen final (após FXAA se ativado) escalada com Nearest-Neighbor para a janela
    canvas_target: rl.c.RenderTexture2D,
    /// Shader de iluminação difusa cartunesca (sem brilho especular Phong)
    lighting_shader: rl.c.Shader,
    /// Shader de pós-processamento FXAA na resolução interna
    fxaa_shader: rl.c.Shader,
    fxaa_res_loc: c_int,
    last_window_size: Vec2 = Vec2.ZERO,
    filtering_mode: TextureFilteringMode,

    pub fn init() DisplaySystem {
        const filtering_mode = getTextureFilteringMode();

        const scene_target = rl.c.LoadRenderTexture(INTERNAL_WIDTH, INTERNAL_HEIGHT);
        // Se FXAA estiver ativo, a textura de entrada do FXAA usa filtro bilinear para suavizar subpixels
        if (ENABLE_FXAA) {
            rl.c.SetTextureFilter(scene_target.texture, rl.c.TEXTURE_FILTER_BILINEAR);
        } else {
            rl.c.SetTextureFilter(scene_target.texture, rl.c.TEXTURE_FILTER_POINT);
        }
        rl.c.SetTextureWrap(scene_target.texture, rl.c.TEXTURE_WRAP_CLAMP);

        const canvas_target = rl.c.LoadRenderTexture(INTERNAL_WIDTH, INTERNAL_HEIGHT);
        // O Canvas final SEMPRE usa Point (Nearest-Neighbor) e ClampToEdge para preservar pixels nítidos na janela
        rl.c.SetTextureFilter(canvas_target.texture, rl.c.TEXTURE_FILTER_POINT);
        rl.c.SetTextureWrap(canvas_target.texture, rl.c.TEXTURE_WRAP_CLAMP);

        const lighting_shader = rl.c.LoadShaderFromMemory(LIGHTING_VS.ptr, LIGHTING_FS.ptr);
        const fxaa_shader = rl.c.LoadShaderFromMemory(null, FXAA_FS.ptr);
        const fxaa_res_loc = rl.c.GetShaderLocation(fxaa_shader, "resolution");
        const res = [2]f32{ @floatFromInt(INTERNAL_WIDTH), @floatFromInt(INTERNAL_HEIGHT) };
        rl.c.SetShaderValue(fxaa_shader, fxaa_res_loc, &res, rl.c.SHADER_UNIFORM_VEC2);

        const win_w: f32 = @floatFromInt(rl.c.GetScreenWidth());
        const win_h: f32 = @floatFromInt(rl.c.GetScreenHeight());
        const h_scale = win_w / @as(f32, @floatFromInt(INTERNAL_WIDTH));
        const v_scale = win_h / @as(f32, @floatFromInt(INTERNAL_HEIGHT));
        const initial_scale = @max(@min(h_scale, v_scale), 0.1);

        std.log.info(
            "Display: Canvas interno inicializado em {d}x{d} (Escala inicial: {d:.2}x, Filtro Textura: {s}, FXAA: {})",
            .{ INTERNAL_WIDTH, INTERNAL_HEIGHT, initial_scale, @tagName(filtering_mode), ENABLE_FXAA },
        );

        return .{
            .scene_target = scene_target,
            .canvas_target = canvas_target,
            .lighting_shader = lighting_shader,
            .fxaa_shader = fxaa_shader,
            .fxaa_res_loc = fxaa_res_loc,
            .last_window_size = Vec2.new(win_w, win_h),
            .filtering_mode = filtering_mode,
        };
    }

    pub fn deinit(self: *DisplaySystem) void {
        rl.c.UnloadShader(self.fxaa_shader);
        rl.c.UnloadShader(self.lighting_shader);
        rl.c.UnloadRenderTexture(self.canvas_target);
        rl.c.UnloadRenderTexture(self.scene_target);
    }

    /// Inicia a renderização 3D dentro do Canvas Offscreen na resolução interna
    pub fn begin3DCanvas(self: *DisplaySystem, camera: rl.c.Camera3D) void {
        rl.c.BeginTextureMode(self.scene_target);
        rl.c.ClearBackground(SKY_COLOR);
        rl.c.BeginMode3D(camera);
    }

    /// Finaliza a cena 3D e desenha o Canvas escalado com Nearest-Neighbor e Letterbox na janela
    pub fn end3DCanvasAndPresent(self: *DisplaySystem) void {
        rl.c.EndMode3D();
        rl.c.EndTextureMode();

        // Se FXAA estiver habilitado, resolve scene_target -> canvas_target na resolução interna
        const final_tex = if (ENABLE_FXAA) blk: {
            rl.c.BeginTextureMode(self.canvas_target);
            rl.c.ClearBackground(SKY_COLOR);
            rl.c.BeginShaderMode(self.fxaa_shader);
            const src_rect = rl.c.Rectangle{
                .x = 0.0,
                .y = 0.0,
                .width = @floatFromInt(self.scene_target.texture.width),
                // OpenGL FBO tem Y invertido
                .height = -@as(f32, @floatFromInt(self.scene_target.texture.height)),
            };
            rl.c.DrawTextureRec(self.scene_target.texture, src_rect, .{ .x = 0.0, .y = 0.0 }, rl.c.WHITE);
            rl.c.EndShaderMode();
            rl.c.EndTextureMode();
            break :blk self.canvas_target.texture;
        } else self.scene_target.texture;

        // Calcula escala preservando aspect ratio (fit_canvas)
        const win_w: f32 = @floatFromInt(rl.c.GetScreenWidth());
        const win_h: f32 = @floatFromInt(rl.c.GetScreenHeight());
        const current_size = Vec2.new(win_w, win_h);

        const int_w: f32 = @floatFromInt(INTERNAL_WIDTH);
        const int_h: f32 = @floatFromInt(INTERNAL_HEIGHT);
        const h_scale = win_w / int_w;
        const v_scale = win_h / int_h;
        const scale = @max(@min(h_scale, v_scale), 0.1);

        if (!current_size.eql(self.last_window_size) and win_w > 0.0 and win_h > 0.0) {
            self.last_window_size = current_size;
            std.log.info(
                "Display: Janela ajustada para ({d:.0}x{d:.0}), escala do canvas: {d:.2}x",
                .{ win_w, win_h, scale },
            );
        }

        const dst_w = int_w * scale;
        const dst_h = int_h * scale;
        const offset_x = (win_w - dst_w) * 0.5;
        const offset_y = (win_h - dst_h) * 0.5;

        // Desenha na janela física com barras pretas (Letterbox / Pillarbox)
        rl.c.BeginDrawing();
        rl.c.ClearBackground(LETTERBOX_COLOR);

        const src = rl.c.Rectangle{
            .x = 0.0,
            .y = 0.0,
            .width = int_w,
            .height = -int_h,
        };
        const dst = rl.c.Rectangle{
            .x = offset_x,
            .y = offset_y,
            .width = dst_w,
            .height = dst_h,
        };
        rl.c.DrawTexturePro(final_tex, src, dst, .{ .x = 0.0, .y = 0.0 }, 0.0, rl.c.WHITE);
        rl.c.EndDrawing();
    }
};
