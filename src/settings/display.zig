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

/// 🖼️ Modo de Escalonamento do Canvas (Resolução Interna -> Resolução da Janela):
pub const CanvasScalingMode = enum {
    /// 👾 Nearest-Neighbor (Point): Pixels nítidos e quadrados ampliados (estilo Retrô / Pixel Art autêntico)
    Nearest,
    /// 🌊 Bilinear: Interpolação linear suave (desfoca a grade de pixels, estilo TV analógica / sem cantos duros)
    Bilinear,
};

/// 🖼️ Escalonamento ativo do Canvas na tela:
/// Alterne entre .Nearest (pixels grandões nítidos) ou .Bilinear (suavizado/macio)
/// 💡 Também pode ser sobrescrito via terminal: $env:CANVAS_SCALING="bilinear" ou "nearest"
pub const CANVAS_SCALING: CanvasScalingMode = .Bilinear;

/// 🎨 Modo de Filtragem das Texturas (Anti-Aliasing do Chão, Terreno e Objetos):
pub const TextureFilteringMode = enum {
    /// 💎 Crisp Pixel AA (Recomendado): Mantém os pixels 100% nítidos, quadrados e vívidos (sem borrão),
    /// mas elimina totalmente o ruído e cintilação (shimmering) em ângulos inclinados/rasantes via shader analítico
    CrispPixelAA,
    /// 👾 Nearest-Neighbor Puro: Pixels nítidos de perto, mas com serrilhado e ruído em ângulos rasantes
    Pixelated,
    /// 🌊 Linear: Interpolação bilinear/trilinear suave clássica (efeito embaçado)
    Linear,
    /// 🛡️ Anisotrópico 16x Clássico: Filtragem anisotrópica padrão
    Anisotropic16x,
};

/// 🎨 Filtragem ativa das texturas:
/// Alterne entre .CrispPixelAA (pixelado vívido sem ruído no horizonte), .Pixelated, .Linear ou .Anisotropic16x
/// 💡 Também pode ser sobrescrito via terminal: $env:TEXTURE_FILTERING="crisp" ou "pixelated"
pub const TEXTURE_FILTERING: TextureFilteringMode = .CrispPixelAA;

/// ✨ Anti-Aliasing de Pós-Processamento (FXAA) na Câmera 3D:
/// • true  = Suaviza a cena 3D inteira (arestas + interior de texturas) na resolução interna
/// • false = Desativado
pub const ENABLE_FXAA: bool = false;

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
pub const TARGET_FPS: ?f32 = null;

// =========================================================================
// 🎚️ CONTROLES DA TRANSIÇÃO CRISP PIXEL ART (NEAR / FAR THRESHOLDS)
// =========================================================================

/// 📏 Distância Near (Threshold Inferior):
/// Abaixo desta distância do jogador/câmera, a textura é 100% pixelada e nítida (zero borrão).
/// 💡 Sobrescreva via terminal: $env:CRISP_NEAR="8.0"
pub const CRISP_DIST_NEAR: f32 = 8.0;

/// 📏 Distância Far (Threshold Superior):
/// Acima desta distância, a textura é 100% filtrada e suave (elimina todo efeito Moiré no horizonte).
/// Entre Near e Far, ocorre uma transição imperceptível (smoothstep).
/// 💡 Sobrescreva via terminal: $env:CRISP_FAR="16.5"
pub const CRISP_DIST_FAR: f32 = 16.5;

/// 🌊 Filtro de suavização aplicado além da distância Far:
/// • .Anisotropic16x: Filtragem anisotrópica de 16 amostras (preserva mais definição em ângulos rasantes)
/// • .Linear: Filtragem trilinear isotrópica (suavização linear mais agressiva contra Moiré)
/// 💡 Sobrescreva via terminal: $env:CRISP_FALLBACK="linear" ou "anisotropic"
pub const CrispFallbackFilter = enum {
    Anisotropic16x,
    Linear,
};

pub const CRISP_FALLBACK: CrispFallbackFilter = .Anisotropic16x;

// =========================================================================
// 📊 PAINEL DE INFORMAÇÕES DE DISPLAY NA TELA (OSD / HUD)
// =========================================================================

/// 📊 Exibir Painel de Informações de Display na Tela (OSD / HUD):
/// • true  = Desenha no canto superior esquerdo as configurações ativas e telemetria
/// • false = Oculta o painel
/// 💡 Também pode ser alternado a qualquer momento durante o jogo pressionando F1
/// 💡 Ou sobrescrito via terminal: $env:SHOW_OVERLAY="true" ou "false"
pub const SHOW_DISPLAY_OVERLAY: bool = true;

/// 🔤 Tamanho base da fonte do Painel OSD na tela (padrão: 20 pixels para leitura nítida e confortável)
/// 💡 Sobrescreva via terminal se desejar: $env:OSD_FONT_SIZE="22"
pub const OSD_FONT_SIZE: i32 = 20;

/// Helper para obter o tamanho da fonte do OSD
pub fn getOsdFontSize() i32 {
    if (rl.getEnv("OSD_FONT_SIZE")) |val| {
        if (std.fmt.parseInt(i32, val, 10)) |s| {
            if (s >= 12 and s <= 40) return s;
        } else |_| {}
    }
    return OSD_FONT_SIZE;
}

/// Helper para obter o estado inicial do OSD respeitando variável de ambiente
pub fn getShowDisplayOverlay() bool {
    if (rl.getEnv("SHOW_OVERLAY")) |val| {
        if (std.ascii.eqlIgnoreCase(val, "false") or
            std.ascii.eqlIgnoreCase(val, "0") or
            std.ascii.eqlIgnoreCase(val, "off") or
            std.ascii.eqlIgnoreCase(val, "no"))
        {
            return false;
        }
        if (std.ascii.eqlIgnoreCase(val, "true") or
            std.ascii.eqlIgnoreCase(val, "1") or
            std.ascii.eqlIgnoreCase(val, "on") or
            std.ascii.eqlIgnoreCase(val, "yes"))
        {
            return true;
        }
    }
    return SHOW_DISPLAY_OVERLAY;
}

/// Helper para obter o threshold Near de CrispPixelAA
pub fn getCrispDistNear() f32 {
    if (rl.getEnv("CRISP_NEAR")) |val| {
        if (std.fmt.parseFloat(f32, val)) |n| {
            if (n >= 0.0) return n;
        } else |_| {}
    }
    return CRISP_DIST_NEAR;
}

/// Helper para obter o threshold Far de CrispPixelAA
pub fn getCrispDistFar() f32 {
    if (rl.getEnv("CRISP_FAR")) |val| {
        if (std.fmt.parseFloat(f32, val)) |f| {
            if (f > 0.0) return f;
        } else |_| {}
    }
    return CRISP_DIST_FAR;
}

/// Helper para obter o modo de filtro fallback (além de Far)
pub fn getCrispFallbackFilter() CrispFallbackFilter {
    if (rl.getEnv("CRISP_FALLBACK")) |val| {
        if (std.ascii.eqlIgnoreCase(val, "linear") or
            std.ascii.eqlIgnoreCase(val, "trilinear") or
            std.ascii.eqlIgnoreCase(val, "smooth"))
        {
            return .Linear;
        }
        if (std.ascii.eqlIgnoreCase(val, "anisotropic") or
            std.ascii.eqlIgnoreCase(val, "af") or
            std.ascii.eqlIgnoreCase(val, "16x"))
        {
            return .Anisotropic16x;
        }
    }
    return CRISP_FALLBACK;
}

/// Helper para obter o modo de escalonamento do canvas respeitando variáveis de ambiente
pub fn getCanvasScalingMode() CanvasScalingMode {
    const val = rl.getEnv("CANVAS_SCALING") orelse return CANVAS_SCALING;
    if (std.ascii.eqlIgnoreCase(val, "bilinear") or
        std.ascii.eqlIgnoreCase(val, "linear") or
        std.ascii.eqlIgnoreCase(val, "smooth"))
    {
        return .Bilinear;
    }
    return .Nearest;
}

/// Helper para obter o modo de filtragem de texturas respeitando variáveis de ambiente
pub fn getTextureFilteringMode() TextureFilteringMode {
    const val = rl.getEnv("TEXTURE_FILTERING") orelse return TEXTURE_FILTERING;

    if (std.ascii.eqlIgnoreCase(val, "crisp") or
        std.ascii.eqlIgnoreCase(val, "crisppixel") or
        std.ascii.eqlIgnoreCase(val, "smart") or
        std.ascii.eqlIgnoreCase(val, "aa"))
    {
        return .CrispPixelAA;
    }
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

/// Configura amostragem de uma textura 2D com fallback específico para o modo CrispPixelAA
pub fn configureModelTextureWithFallback(texture: *rl.c.Texture2D, mode: TextureFilteringMode, fallback: CrispFallbackFilter) void {
    if (texture.id == 0) return;

    // Garante repetição (Tiling) em U e V para evitar estiramento nas rampas
    rl.c.SetTextureWrap(texture.*, rl.c.TEXTURE_WRAP_REPEAT);

    switch (mode) {
        .CrispPixelAA => {
            // No modo CrispPixelAA, o shader calcula analiticamente a borda nítida de cada pixel,
            // e o hardware (Anisotrópico 16x ou Linear) elimina o ruído/shimmering no horizonte
            if (texture.mipmaps <= 1) {
                rl.c.GenTextureMipmaps(texture);
            }
            // Anisotropia nao configura MIN/MAG; aplique-a por ultimo, pois rlgl a reseta ao alterar parametros.
            rl.c.SetTextureFilter(texture.*, rl.c.TEXTURE_FILTER_TRILINEAR);
            if (fallback == .Anisotropic16x) {
                rl.c.SetTextureFilter(texture.*, rl.c.TEXTURE_FILTER_ANISOTROPIC_16X);
            }
        },
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
            rl.c.SetTextureFilter(texture.*, rl.c.TEXTURE_FILTER_TRILINEAR);
            rl.c.SetTextureFilter(texture.*, rl.c.TEXTURE_FILTER_ANISOTROPIC_16X);
        },
    }
}

/// Configura amostragem de uma textura 2D (Pixelated, Linear ou Anisotrópico 16x) mantendo Tiling (Repeat) com o fallback padrão
pub fn configureModelTexture(texture: *rl.c.Texture2D, mode: TextureFilteringMode) void {
    configureModelTextureWithFallback(texture, mode, getCrispFallbackFilter());
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
    \\uniform int useCrispPixelAA;
    \\uniform vec3 cameraPos;
    \\uniform float crispNear;
    \\uniform float crispFar;
    \\out vec4 finalColor;
    \\void main() {
    \\    vec4 baseTex;
    \\    if (useCrispPixelAA == 1) {
    \\        // 💎 Amostragem Analítica de Pixel Art (Fat-Pixel AA):
    \\        vec2 texSize = vec2(textureSize(texture0, 0));
    \\        vec2 uv = fragTexCoord * texSize;
    \\        vec2 duv_dx = dFdx(uv);
    \\        vec2 duv_dy = dFdy(uv);
    \\        vec2 w = max(abs(duv_dx), abs(duv_dy));
    \\        vec2 u_shifted = uv - 0.5;
    \\        vec2 u_floor = floor(u_shifted);
    \\        vec2 u_fract = u_shifted - u_floor;
    \\        vec2 t = clamp((u_fract - 0.5) / max(w, vec2(0.0001)) + 0.5, 0.0, 1.0);
    \\        vec2 final_uv = (u_floor + t + 0.5) / texSize;
    \\
    \\        // Amostra nítida mantendo os blocos de pixel art
    \\        vec4 sharpSample = textureGrad(texture0, final_uv, dFdx(fragTexCoord) * 0.5, dFdy(fragTexCoord) * 0.5);
    \\
    \\        // Amostra suave com filtragem de hardware (elimina 100% de Moiré no horizonte)
    \\        vec4 smoothSample = texture(texture0, fragTexCoord);
    \\
    \\        // Transição suave ajustável por distância da câmera (Near -> Far)
    \\        float dist = length(fragPosition - cameraPos);
    \\        float blend = smoothstep(crispNear, max(crispFar, crispNear + 0.1), dist);
    \\        baseTex = mix(sharpSample, smoothSample, blend);
    \\    } else {
    \\        baseTex = texture(texture0, fragTexCoord);
    \\    }
    \\    vec4 texelColor = baseTex * colDiffuse * fragColor;
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

// =========================================================================
// 🔷 MSAA OFFSCREEN (Framebuffer multisample com resolve para o canvas)
// =========================================================================
// O flag FLAG_MSAA_4X_HINT só afeta o framebuffer da janela. Como o 3D é desenhado
// num RenderTexture offscreen, criamos um FBO multisample próprio e fazemos o resolve
// (glBlitFramebuffer) para o scene_target antes do FXAA/apresentação.

/// Número de amostras do MSAA offscreen
pub const MSAA_SAMPLES: c_int = 4;

extern fn glfwGetProcAddress(name: [*:0]const u8) callconv(.c) ?*const anyopaque;

const GL_FRAMEBUFFER: c_uint = 0x8D40;
const GL_READ_FRAMEBUFFER: c_uint = 0x8CA8;
const GL_DRAW_FRAMEBUFFER: c_uint = 0x8CA9;
const GL_RENDERBUFFER: c_uint = 0x8D41;
const GL_COLOR_ATTACHMENT0: c_uint = 0x8CE0;
const GL_DEPTH_ATTACHMENT: c_uint = 0x8D00;
const GL_RGBA8: c_uint = 0x8058;
const GL_DEPTH_COMPONENT24: c_uint = 0x81A6;
const GL_COLOR_BUFFER_BIT: c_uint = 0x4000;
const GL_NEAREST: c_uint = 0x2600;
const GL_FRAMEBUFFER_COMPLETE: c_uint = 0x8CD5;

const GlFns = struct {
    genFramebuffers: *const fn (c_int, *c_uint) callconv(.c) void,
    deleteFramebuffers: *const fn (c_int, *const c_uint) callconv(.c) void,
    bindFramebuffer: *const fn (c_uint, c_uint) callconv(.c) void,
    genRenderbuffers: *const fn (c_int, *c_uint) callconv(.c) void,
    deleteRenderbuffers: *const fn (c_int, *const c_uint) callconv(.c) void,
    bindRenderbuffer: *const fn (c_uint, c_uint) callconv(.c) void,
    renderbufferStorageMultisample: *const fn (c_uint, c_int, c_uint, c_int, c_int) callconv(.c) void,
    framebufferRenderbuffer: *const fn (c_uint, c_uint, c_uint, c_uint) callconv(.c) void,
    checkFramebufferStatus: *const fn (c_uint) callconv(.c) c_uint,
    blitFramebuffer: *const fn (c_int, c_int, c_int, c_int, c_int, c_int, c_int, c_int, c_uint, c_uint) callconv(.c) void,
};

fn loadGlFns() ?GlFns {
    const names = .{
        "glGenFramebuffers",                "glDeleteFramebuffers",      "glBindFramebuffer",
        "glGenRenderbuffers",               "glDeleteRenderbuffers",     "glBindRenderbuffer",
        "glRenderbufferStorageMultisample", "glFramebufferRenderbuffer", "glCheckFramebufferStatus",
        "glBlitFramebuffer",
    };
    var ptrs: [names.len]*const anyopaque = undefined;
    inline for (names, 0..) |n, i| {
        ptrs[i] = glfwGetProcAddress(n) orelse return null;
    }
    return GlFns{
        .genFramebuffers = @ptrCast(@alignCast(ptrs[0])),
        .deleteFramebuffers = @ptrCast(@alignCast(ptrs[1])),
        .bindFramebuffer = @ptrCast(@alignCast(ptrs[2])),
        .genRenderbuffers = @ptrCast(@alignCast(ptrs[3])),
        .deleteRenderbuffers = @ptrCast(@alignCast(ptrs[4])),
        .bindRenderbuffer = @ptrCast(@alignCast(ptrs[5])),
        .renderbufferStorageMultisample = @ptrCast(@alignCast(ptrs[6])),
        .framebufferRenderbuffer = @ptrCast(@alignCast(ptrs[7])),
        .checkFramebufferStatus = @ptrCast(@alignCast(ptrs[8])),
        .blitFramebuffer = @ptrCast(@alignCast(ptrs[9])),
    };
}

const MsaaTarget = struct {
    fbo: c_uint = 0,
    color_rb: c_uint = 0,
    depth_rb: c_uint = 0,
};

/// Informações de hardware, taxa de quadros e estado para exibição no painel OSD
pub const OverlayInfo = struct {
    gpu_name: []const u8,
    fps: f32,
    frametime_ms: f32,
    target_fps: ?f32,
    vsync: bool,
};

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
    camera_pos_loc: c_int,
    crisp_near_loc: c_int,
    crisp_far_loc: c_int,
    crisp_mode_loc: c_int,
    crisp_near_val: f32,
    crisp_far_val: f32,
    crisp_fallback: CrispFallbackFilter,
    canvas_scaling: CanvasScalingMode,
    enable_fxaa: bool,
    show_overlay: bool,
    osd_font: rl.c.Font,
    gl: ?GlFns,
    msaa: MsaaTarget,
    msaa_enabled: bool,
    last_window_size: Vec2 = Vec2.ZERO,
    filtering_mode: TextureFilteringMode,

    pub fn init() DisplaySystem {
        const filtering_mode = getTextureFilteringMode();
        const canvas_scaling = getCanvasScalingMode();
        const crisp_fallback = getCrispFallbackFilter();
        const show_overlay = getShowDisplayOverlay();
        const enable_fxaa = ENABLE_FXAA;

        // Carrega fonte vetorial TrueType (Arial) para renderização nítida, suave e altamente legível do OSD
        const font_path: ?[:0]const u8 = blk: {
            if (rl.c.FileExists("assets/fonts/arial.ttf")) break :blk "assets/fonts/arial.ttf";
            if (rl.c.FileExists("_ZIG/assets/fonts/arial.ttf")) break :blk "_ZIG/assets/fonts/arial.ttf";
            if (rl.c.FileExists("C:\\Windows\\Fonts\\arial.ttf")) break :blk "C:\\Windows\\Fonts\\arial.ttf";
            break :blk null;
        };

        const osd_font = if (font_path) |path| font_blk: {
            const portuguese_codepoints = [_]c_int{
                0x00C7, 0x00E7, // Ç ç
                0x00C3, 0x00E3, // Ã ã
                0x00D5, 0x00F5, // Õ õ
                0x00C1, 0x00E1, // Á á
                0x00C2, 0x00E2, // Â â
                0x00C9, 0x00E9, // É é
                0x00CA, 0x00EA, // Ê ê
                0x00CD, 0x00ED, // Í í
                0x00D3, 0x00F3, // Ó ó
                0x00D4, 0x00F4, // Ô ô
                0x00DA, 0x00FA, // Ú ú
            };
            const osd_codepoints = comptime blk: {
                var codepoints: [95 + portuguese_codepoints.len]c_int = undefined;
                for (0..95) |index| {
                    codepoints[index] = @intCast(index + 32);
                }
                for (portuguese_codepoints, 0..) |codepoint, index| {
                    codepoints[95 + index] = codepoint;
                }
                break :blk codepoints;
            };
            const f = rl.c.LoadFontEx(path.ptr, 48, @constCast(&osd_codepoints), @intCast(osd_codepoints.len));
            if (f.texture.id != 0) {
                rl.c.SetTextureFilter(f.texture, rl.c.TEXTURE_FILTER_BILINEAR);
                std.log.info("Display: Fonte TrueType Arial carregada com sucesso ({s})", .{path});
                break :font_blk f;
            }
            std.log.warn("Display: Falha ao carregar fonte ({s}), usando fonte padrao", .{path});
            break :font_blk rl.c.GetFontDefault();
        } else rl.c.GetFontDefault();

        const scene_target = rl.c.LoadRenderTexture(INTERNAL_WIDTH, INTERNAL_HEIGHT);
        // Se FXAA estiver ativo, a textura de entrada do FXAA usa filtro bilinear para suavizar subpixels
        if (enable_fxaa) {
            rl.c.SetTextureFilter(scene_target.texture, rl.c.TEXTURE_FILTER_BILINEAR);
        } else {
            switch (canvas_scaling) {
                .Nearest => rl.c.SetTextureFilter(scene_target.texture, rl.c.TEXTURE_FILTER_POINT),
                .Bilinear => rl.c.SetTextureFilter(scene_target.texture, rl.c.TEXTURE_FILTER_BILINEAR),
            }
        }
        rl.c.SetTextureWrap(scene_target.texture, rl.c.TEXTURE_WRAP_CLAMP);

        // Cria o framebuffer multisample (MSAA) offscreen
        const gl = loadGlFns();
        var msaa = MsaaTarget{};
        if (gl) |g| {
            g.genFramebuffers(1, &msaa.fbo);
            g.genRenderbuffers(1, &msaa.color_rb);
            g.bindRenderbuffer(GL_RENDERBUFFER, msaa.color_rb);
            g.renderbufferStorageMultisample(GL_RENDERBUFFER, MSAA_SAMPLES, GL_RGBA8, INTERNAL_WIDTH, INTERNAL_HEIGHT);
            g.genRenderbuffers(1, &msaa.depth_rb);
            g.bindRenderbuffer(GL_RENDERBUFFER, msaa.depth_rb);
            g.renderbufferStorageMultisample(GL_RENDERBUFFER, MSAA_SAMPLES, GL_DEPTH_COMPONENT24, INTERNAL_WIDTH, INTERNAL_HEIGHT);
            g.bindFramebuffer(GL_FRAMEBUFFER, msaa.fbo);
            g.framebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, msaa.color_rb);
            g.framebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, msaa.depth_rb);
            const status = g.checkFramebufferStatus(GL_FRAMEBUFFER);
            g.bindFramebuffer(GL_FRAMEBUFFER, 0);
            if (status != GL_FRAMEBUFFER_COMPLETE) {
                std.log.warn("Display: FBO MSAA incompleto (0x{x}), MSAA desativado", .{status});
                msaa = MsaaTarget{};
            }
        } else {
            std.log.warn("Display: funcoes GL de MSAA indisponiveis, MSAA desativado", .{});
        }
        const msaa_enabled = !DISABLE_MSAA and msaa.fbo != 0;

        const canvas_target = rl.c.LoadRenderTexture(INTERNAL_WIDTH, INTERNAL_HEIGHT);
        // Filtro de apresentação do Canvas na janela física (Nearest vs Bilinear)
        switch (canvas_scaling) {
            .Nearest => rl.c.SetTextureFilter(canvas_target.texture, rl.c.TEXTURE_FILTER_POINT),
            .Bilinear => rl.c.SetTextureFilter(canvas_target.texture, rl.c.TEXTURE_FILTER_BILINEAR),
        }
        rl.c.SetTextureWrap(canvas_target.texture, rl.c.TEXTURE_WRAP_CLAMP);

        const lighting_shader = rl.c.LoadShaderFromMemory(LIGHTING_VS.ptr, LIGHTING_FS.ptr);
        const crisp_loc = rl.c.GetShaderLocation(lighting_shader, "useCrispPixelAA");
        const crisp_val: c_int = if (filtering_mode == .CrispPixelAA) 1 else 0;
        if (!rl.c.IsShaderValid(lighting_shader) or crisp_loc < 0) {
            std.log.err("Display: shader de iluminacao invalido ou uniforme useCrispPixelAA ausente (loc={d})", .{crisp_loc});
        }
        rl.c.SetShaderValue(lighting_shader, crisp_loc, &crisp_val, rl.c.SHADER_UNIFORM_INT);

        const camera_pos_loc = rl.c.GetShaderLocation(lighting_shader, "cameraPos");
        const crisp_near_loc = rl.c.GetShaderLocation(lighting_shader, "crispNear");
        const crisp_far_loc = rl.c.GetShaderLocation(lighting_shader, "crispFar");

        const near_val = getCrispDistNear();
        const far_val = getCrispDistFar();
        rl.c.SetShaderValue(lighting_shader, crisp_near_loc, &near_val, rl.c.SHADER_UNIFORM_FLOAT);
        rl.c.SetShaderValue(lighting_shader, crisp_far_loc, &far_val, rl.c.SHADER_UNIFORM_FLOAT);

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
            "Display: Canvas interno {d}x{d} (Escala: {d:.2}x, Canvas: {s}, Texturas: {s}, Fallback: {s}, Near: {d:.1}, Far: {d:.1}, FXAA: {}, OSD: {})",
            .{ INTERNAL_WIDTH, INTERNAL_HEIGHT, initial_scale, @tagName(canvas_scaling), @tagName(filtering_mode), @tagName(crisp_fallback), near_val, far_val, enable_fxaa, show_overlay },
        );

        return .{
            .scene_target = scene_target,
            .canvas_target = canvas_target,
            .lighting_shader = lighting_shader,
            .fxaa_shader = fxaa_shader,
            .fxaa_res_loc = fxaa_res_loc,
            .camera_pos_loc = camera_pos_loc,
            .crisp_near_loc = crisp_near_loc,
            .crisp_far_loc = crisp_far_loc,
            .crisp_mode_loc = crisp_loc,
            .crisp_near_val = near_val,
            .crisp_far_val = far_val,
            .crisp_fallback = crisp_fallback,
            .canvas_scaling = canvas_scaling,
            .enable_fxaa = enable_fxaa,
            .show_overlay = show_overlay,
            .osd_font = osd_font,
            .gl = gl,
            .msaa = msaa,
            .msaa_enabled = msaa_enabled,
            .last_window_size = Vec2.new(win_w, win_h),
            .filtering_mode = filtering_mode,
        };
    }

    pub fn deinit(self: *DisplaySystem) void {
        if (self.gl) |g| {
            if (self.msaa.fbo != 0) {
                g.deleteFramebuffers(1, &self.msaa.fbo);
                g.deleteRenderbuffers(1, &self.msaa.color_rb);
                g.deleteRenderbuffers(1, &self.msaa.depth_rb);
            }
        }
        if (self.osd_font.texture.id != 0 and self.osd_font.texture.id != rl.c.GetFontDefault().texture.id) {
            rl.c.UnloadFont(self.osd_font);
        }
        rl.c.UnloadShader(self.fxaa_shader);
        rl.c.UnloadShader(self.lighting_shader);
        rl.c.UnloadRenderTexture(self.canvas_target);
        rl.c.UnloadRenderTexture(self.scene_target);
    }

    /// Alterna o MSAA offscreen (ON <-> OFF) em tempo real
    pub fn toggleMsaa(self: *DisplaySystem) bool {
        if (self.msaa.fbo != 0) self.msaa_enabled = !self.msaa_enabled;
        return self.msaa_enabled;
    }

    /// Alterna a visibilidade do OSD (HUD) na tela
    pub fn toggleOverlay(self: *DisplaySystem) bool {
        self.show_overlay = !self.show_overlay;
        return self.show_overlay;
    }

    /// Cicla o modo de filtragem de texturas entre os 4 modos disponíveis
    pub fn cycleTextureFiltering(self: *DisplaySystem) TextureFilteringMode {
        const next: TextureFilteringMode = switch (self.filtering_mode) {
            .CrispPixelAA => .Pixelated,
            .Pixelated => .Linear,
            .Linear => .Anisotropic16x,
            .Anisotropic16x => .CrispPixelAA,
        };
        self.filtering_mode = next;
        self.applyTextureFilteringMode();
        return next;
    }

    /// Sincroniza o uniforme do shader com o modo de filtragem atualmente selecionado.
    pub fn applyTextureFilteringMode(self: *const DisplaySystem) void {
        if (!rl.c.IsShaderValid(self.lighting_shader) or self.crisp_mode_loc < 0) return;
        const crisp_val: c_int = if (self.filtering_mode == .CrispPixelAA) 1 else 0;
        rl.c.SetShaderValue(self.lighting_shader, self.crisp_mode_loc, &crisp_val, rl.c.SHADER_UNIFORM_INT);
    }

    /// Alterna o escalonamento do canvas na janela (Nearest <-> Bilinear)
    pub fn toggleCanvasScaling(self: *DisplaySystem) CanvasScalingMode {
        self.canvas_scaling = switch (self.canvas_scaling) {
            .Nearest => .Bilinear,
            .Bilinear => .Nearest,
        };
        const filter = switch (self.canvas_scaling) {
            .Nearest => rl.c.TEXTURE_FILTER_POINT,
            .Bilinear => rl.c.TEXTURE_FILTER_BILINEAR,
        };
        rl.c.SetTextureFilter(self.canvas_target.texture, filter);
        if (!self.enable_fxaa) {
            rl.c.SetTextureFilter(self.scene_target.texture, filter);
        }
        return self.canvas_scaling;
    }

    /// Alterna o pós-processamento FXAA (ON <-> OFF)
    pub fn toggleFxaa(self: *DisplaySystem) bool {
        self.enable_fxaa = !self.enable_fxaa;
        if (self.enable_fxaa) {
            rl.c.SetTextureFilter(self.scene_target.texture, rl.c.TEXTURE_FILTER_BILINEAR);
        } else {
            const filter = switch (self.canvas_scaling) {
                .Nearest => rl.c.TEXTURE_FILTER_POINT,
                .Bilinear => rl.c.TEXTURE_FILTER_BILINEAR,
            };
            rl.c.SetTextureFilter(self.scene_target.texture, filter);
        }
        return self.enable_fxaa;
    }

    /// Alterna o filtro de fallback além de Far (Anisotropic16x <-> Linear)
    pub fn toggleCrispFallback(self: *DisplaySystem) CrispFallbackFilter {
        self.crisp_fallback = switch (self.crisp_fallback) {
            .Anisotropic16x => .Linear,
            .Linear => .Anisotropic16x,
        };
        return self.crisp_fallback;
    }

    /// Atualiza dinamicamente os limites de distância da filtragem Crisp Pixel AA
    pub fn setCrispThresholds(self: *DisplaySystem, near: f32, far: f32) void {
        self.crisp_near_val = @max(0.0, near);
        self.crisp_far_val = @max(self.crisp_near_val + 0.1, far);
        rl.c.SetShaderValue(self.lighting_shader, self.crisp_near_loc, &self.crisp_near_val, rl.c.SHADER_UNIFORM_FLOAT);
        rl.c.SetShaderValue(self.lighting_shader, self.crisp_far_loc, &self.crisp_far_val, rl.c.SHADER_UNIFORM_FLOAT);
    }

    /// Inicia a renderização 3D dentro do Canvas Offscreen na resolução interna
    pub fn begin3DCanvas(self: *DisplaySystem, camera: rl.c.Camera3D) void {
        if (self.filtering_mode == .CrispPixelAA) {
            const cam_pos = [3]f32{ camera.position.x, camera.position.y, camera.position.z };
            rl.c.SetShaderValue(self.lighting_shader, self.camera_pos_loc, &cam_pos, rl.c.SHADER_UNIFORM_VEC3);
        }
        rl.c.BeginTextureMode(self.scene_target);
        if (self.msaa_enabled) {
            if (self.gl) |g| {
                g.bindFramebuffer(GL_FRAMEBUFFER, self.msaa.fbo);
            }
        }
        rl.c.ClearBackground(SKY_COLOR);
        rl.c.BeginMode3D(camera);
    }

    fn printZ(buf: []u8, comptime fmt: []const u8, args: anytype) [:0]const u8 {
        if (buf.len == 0) return "";
        const slice = std.fmt.bufPrint(buf[0 .. buf.len - 1], fmt, args) catch return "";
        buf[slice.len] = 0;
        return buf[0..slice.len :0];
    }

    /// Desenha o painel OSD no canto superior esquerdo da tela (resolução nativa da janela com fonte vetorial Arial)
    pub fn drawOverlay(
        self: *const DisplaySystem,
        info: OverlayInfo,
    ) void {
        if (!self.show_overlay) return;

        const font = self.osd_font;
        const drawOsdText = struct {
            fn call(f: rl.c.Font, text: [:0]const u8, posX: i32, posY: i32, fontSize: f32, color: rl.c.Color) void {
                const pos = rl.c.Vector2{ .x = @floatFromInt(posX), .y = @floatFromInt(posY) };
                rl.c.DrawTextEx(f, text.ptr, pos, fontSize, 1.0, color);
            }
        }.call;

        const base_font: i32 = getOsdFontSize();
        const base_font_f: f32 = @floatFromInt(base_font);
        const pad_x: i32 = 14;
        const pad_y: i32 = 14;
        const line_h: i32 = base_font + 9;
        const box_w: f32 = 790.0;
        const box_h: f32 = @floatFromInt(line_h * 8 + 56);

        // Fundo escuro semi-transparente elegante
        const bg_rect = rl.c.Rectangle{
            .x = @floatFromInt(pad_x),
            .y = @floatFromInt(pad_y),
            .width = box_w,
            .height = box_h,
        };
        rl.c.DrawRectangleRounded(bg_rect, 0.06, 4, rl.c.Color{ .r = 10, .g = 14, .b = 22, .a = 230 });
        rl.c.DrawRectangleRoundedLines(bg_rect, 0.06, 4, rl.c.Color{ .r = 65, .g = 100, .b = 145, .a = 245 });

        const x: i32 = pad_x + 16;
        var y: i32 = pad_y + 12;

        // Cabeçalho
        drawOsdText(font, "[DISPLAY OSD - F1: Ocultar]", x, y, base_font_f + 3.0, rl.c.Color{ .r = 255, .g = 215, .b = 75, .a = 255 });
        y += line_h + 3;

        // Linha 1: GPU & FPS
        var buf1: [160]u8 = undefined;
        var cap_buf: [32]u8 = undefined;
        const cap_str = if (info.target_fps) |tf|
            (std.fmt.bufPrint(&cap_buf, "{d:.0} FPS", .{tf}) catch "60 FPS")
        else
            "Livre";

        const display_gpu = if (info.gpu_name.len > 26) info.gpu_name[0..26] else info.gpu_name;
        const text1 = printZ(&buf1, "GPU: {s} | FPS: {d:.0} ({d:.2}ms) | Cap [F5]: {s}", .{ display_gpu, info.fps, info.frametime_ms, cap_str });
        drawOsdText(font, text1, x, y, base_font_f, rl.c.Color{ .r = 225, .g = 235, .b = 250, .a = 255 });
        y += line_h;

        // Linha 2: Texturas e Filtro
        var buf2: [160]u8 = undefined;
        const filter_name = switch (self.filtering_mode) {
            .CrispPixelAA => "CrispPixelAA (Smart AA)",
            .Pixelated => "Pixelated (Nearest Puro)",
            .Linear => "Linear (Trilinear)",
            .Anisotropic16x => "Anisotropic 16x",
        };
        const text2 = printZ(&buf2, "Filtro Textura [F2]: {s}", .{filter_name});
        const filter_color = switch (self.filtering_mode) {
            .CrispPixelAA => rl.c.Color{ .r = 100, .g = 240, .b = 150, .a = 255 },
            .Pixelated => rl.c.Color{ .r = 255, .g = 200, .b = 80, .a = 255 },
            .Linear => rl.c.Color{ .r = 180, .g = 200, .b = 245, .a = 255 },
            .Anisotropic16x => rl.c.Color{ .r = 130, .g = 210, .b = 255, .a = 255 },
        };
        drawOsdText(font, text2, x, y, base_font_f, filter_color);
        y += line_h;

        // Linha 3: Se CrispPixelAA, mostra Near, Far e Fallback
        var buf3: [160]u8 = undefined;
        if (self.filtering_mode == .CrispPixelAA) {
            const fb_str = switch (self.crisp_fallback) {
                .Anisotropic16x => "Aniso16x",
                .Linear => "Trilinear",
            };
            const text3 = printZ(
                &buf3,
                "  -> Near [F6/F7]: {d:.1} | Far [F8/F9]: {d:.1} | Fallback [F10]: {s}",
                .{ self.crisp_near_val, self.crisp_far_val, fb_str },
            );
            drawOsdText(font, text3, x, y, base_font_f - 2.0, rl.c.Color{ .r = 130, .g = 225, .b = 255, .a = 255 });
        } else {
            const text3 = "  -> Limites Near/Far ativos apenas quando Filtro = CrispPixelAA";
            drawOsdText(font, text3, x, y, base_font_f - 2.0, rl.c.Color{ .r = 150, .g = 160, .b = 175, .a = 220 });
        }
        y += line_h;

        // Linha 4: Canvas, FXAA, MSAA e VSync
        var buf4: [160]u8 = undefined;
        const canvas_str = switch (self.canvas_scaling) {
            .Nearest => "Nearest",
            .Bilinear => "Bilinear",
        };
        const fxaa_str = if (self.enable_fxaa) "ON" else "OFF";
        const msaa_str = if (self.msaa_enabled) "ON" else "OFF";
        const vsync_str = if (info.vsync) "ON" else "OFF";
        const text4 = printZ(
            &buf4,
            "Canvas [F3]: {s} | FXAA [F4]: {s} | MSAA 4x [F11]: {s} | VSync: {s}",
            .{ canvas_str, fxaa_str, msaa_str, vsync_str },
        );
        drawOsdText(font, text4, x, y, base_font_f, rl.c.Color{ .r = 200, .g = 215, .b = 230, .a = 255 });
        y += line_h;

        // Linha 5: Estado de tela cheia e atalho
        const fullscreen_text = if (rl.c.IsWindowFullscreen()) "TELA CHEIA" else "JANELA";
        var buf5: [96]u8 = undefined;
        const text5 = printZ(&buf5, "Modo de exibição [F12]: {s}", .{fullscreen_text});
        drawOsdText(font, text5, x, y, base_font_f, rl.c.Color{ .r = 200, .g = 215, .b = 230, .a = 255 });
        y += line_h;

        // Separador entre telemetria/configuração atual e atalhos
        const divider_y = y + 2;
        rl.c.DrawLine(x, divider_y, @intFromFloat(@as(f32, @floatFromInt(pad_x)) + box_w - 16.0), divider_y, rl.c.Color{ .r = 65, .g = 100, .b = 145, .a = 210 });

        // Atalhos organizados em grade 3x3 para manter todos dentro do painel
        const shortcut_rows = [_][3][:0]const u8{
            .{ "[F1] HUD", "[F2] Filtro", "[F3] Canvas" },
            .{ "[F4] FXAA", "[F5] FPS", "[F6-F9] Near/Far" },
            .{ "[F10] Fallback", "[F11] MSAA", "[F12] Tela cheia" },
        };
        const shortcut_color = rl.c.Color{ .r = 145, .g = 165, .b = 190, .a = 230 };
        const column_step: i32 = 250;
        const shortcut_step: i32 = line_h - 4;
        const shortcut_start_y = divider_y + 10;
        for (shortcut_rows, 0..) |row, row_index| {
            for (row, 0..) |shortcut, column_index| {
                const shortcut_x = x + @as(i32, @intCast(column_index)) * column_step;
                const shortcut_y = shortcut_start_y + @as(i32, @intCast(row_index)) * shortcut_step;
                drawOsdText(font, shortcut, shortcut_x, shortcut_y, base_font_f - 3.0, shortcut_color);
            }
        }
    }

    /// Finaliza a cena 3D e desenha o Canvas escalado com Nearest-Neighbor e Letterbox na janela
    pub fn end3DCanvasAndPresent(self: *DisplaySystem, overlay_info: ?OverlayInfo) void {
        rl.c.EndMode3D();
        if (self.msaa_enabled) {
            // Resolve MSAA: copia o FBO multisample para o scene_target (média das amostras)
            if (self.gl) |g| {
                g.bindFramebuffer(GL_READ_FRAMEBUFFER, self.msaa.fbo);
                g.bindFramebuffer(GL_DRAW_FRAMEBUFFER, self.scene_target.id);
                g.blitFramebuffer(0, 0, INTERNAL_WIDTH, INTERNAL_HEIGHT, 0, 0, INTERNAL_WIDTH, INTERNAL_HEIGHT, GL_COLOR_BUFFER_BIT, GL_NEAREST);
                g.bindFramebuffer(GL_FRAMEBUFFER, self.scene_target.id);
            }
        }
        rl.c.EndTextureMode();

        // Se FXAA estiver habilitado, resolve scene_target -> canvas_target na resolução interna
        const final_tex = if (self.enable_fxaa) blk: {
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

        // Painel OSD de informações de tela e telemetria
        if (overlay_info) |info| {
            self.drawOverlay(info);
        }

        rl.c.EndDrawing();
    }
};
