# Documento de Contexto: Plataforma 3D Retrô (Zig + Raylib 5.5)

> **Finalidade deste documento:** Servir como fonte única da verdade sobre a arquitetura, decisões técnicas, problemas solucionados e estado atual do código para permitir que o desenvolvimento continue em qualquer outro computador sem perda de contexto.

---

## 1. Visão Geral e Direção Artística

* **Conceito:** Jogo de plataforma 3D retrô inspirado na estética e na física de *Super Mario 64* (especificamente a direção de arte e estilo do port para Nintendo DS: *Super Mario 64 DS*).
* **Direção Visual:**
  * **Renderização Interna em Baixa Resolução (Canvas Offscreen):** O mundo 3D é desenhado internamente em um *Framebuffer Offscreen* (`RenderTexture2D`, padrão `854 × 480` ou `256 × 144` em 16:9 widescreen), e escalado para a janela física via **Nearest-Neighbor (`TEXTURE_FILTER_POINT`)**, gerando pixels nítidos e bem definidos com preservação de proporção (*Letterbox / Pillarbox*).
  * **Filtragem de Texturas Configurável com Tiling:** Suporte imediato a amostragem **Pixelated** (`TEXTURE_FILTER_POINT`), **Linear** (`TEXTURE_FILTER_TRILINEAR`) ou **Anisotrópico 16x** (`TEXTURE_FILTER_ANISOTROPIC_16X` com geração automática de mipmaps) combinada com repetição contínua (`TEXTURE_WRAP_REPEAT`).
  * **Iluminação Cartunesca Pura (Shader GLSL 330 Sem Phong/Specular):** Shader customizado de iluminação direcional solar `(10, 20, 10)` com preenchimento de luz ambiente viva (`0.58 + 0.42 * NdotL`), eliminando brilhos especulares plásticos e suportando malhas de face dupla (`doubleSided`).
  * **Anti-Aliasing Duplo (MSAA 4x + Pós-Processamento FXAA):** Suavização geométrica de bordas (`FLAG_MSAA_4X_HINT`) aliada a um shader GLSL 330 de **FXAA** executado estritamente na resolução interna antes do escalonamento Nearest-Neighbor para a janela.
* **Paradigma de Desenvolvimento:** Baixo nível, código nativo compilado em **Zig (`0.17.0-dev`)** com **Raylib 5.5 (OpenGL 3.3 Core)** compilada diretamente do código-fonte C via `zig cc`, gerando um binário autocontido, multiplataforma e ultraleve (~4.6 MB em Debug).

---

## 2. Decisões Arquiteturais e Stack Principal (`_ZIG/`)

1. **Stack Central:** **Zig (`0.17.0-dev`) + Raylib 5.5 + Blender (`.glb` / glTF 2.0)**.
   * **Por que Zig + Raylib:** A migração do protótipo inicial em Rust/Bevy para Zig + Raylib reduziu o tamanho do executável de >80 MB para ~4.6 MB, eliminou o overhead da pipeline PBR pesada do WGPU, garantiu tempos de compilação incrementais de ~2 segundos e atingiu **60.0 FPS cravados (`16.67ms`) com Jitter ($\sigma$) de apenas `0.02ms` e zero spikes**.
   * **Compilação C Integrada (`zig cc`):** O código-fonte oficial em C99 da Raylib 5.5 (`_ZIG/vendor/raylib/src`) é compilado diretamente pelo sistema de build do Zig (`_ZIG/build.zig`), sem depender de bibliotecas pré-compiladas externas ou wrappers de terceiros.
   * **Pipeline de Assets:** O Blender exporta cenários e modelos diretamente em formato `.glb` (glTF 2.0 binário com texturas PNG embutidas), carregados nativamente via `LoadModel` da Raylib (`cgltf`).

2. **Hierarquia Modular de Responsabilidades (`_ZIG/src/`):**
   ```text
   _ZIG/
   ├── build.zig                        # Script de build (Zig 0.17) + compilação C da Raylib 5.5
   ├── build.zig.zon                    # Manifesto do pacote Zig
   ├── assets/                          # Modelos .glb (Scene.glb) e texturas (tile.png)
   ├── vendor/raylib/src/               # Código-fonte C99 oficial da Raylib 5.5 e GLFW
   └── src/
       ├── main.zig                     # Ponto de entrada e loop principal (Update / PostUpdate / Render)
       ├── c_headers.h                  # Header unificado traduzido via addTranslateC
       ├── gpu_optimus.c                # Exportação PE (NvOptimusEnablement / AMD PowerXpress)
       ├── rl.zig                       # Ponte tipada para Raylib, RLGL e Raymath
       ├── math.zig                     # Matemática 3D (Vec2, Vec3, Quat com slerp)
       ├── settings/
       │   ├── mod.zig
       │   ├── display.zig              # Resolução, Canvas Offscreen, Shaders GLSL (Luz DS + FXAA) e Filtros
       │   └── diagnostics.zig          # Detecção de GPU OpenGL, FPS Cap de alta precisão e Telemetria
       └── scene/
           ├── mod.zig
           ├── camera/
           │   ├── mod.zig
           │   └── camera.zig           # Câmera orbital estilo Lakitu (Super Mario 64)
           ├── player/
           │   ├── mod.zig
           │   └── player.zig           # Física SM64 (inércia, skid, pulo variável, tilt) e Stats
           ├── world/
           │   ├── mod.zig
           │   ├── collision.zig        # Colisão estática determinística (Piso/Parede/Teto) + Grade XZ
           │   └── terrain.zig          # Carregamento de fases .glb e extração de triângulos
           └── objects/
               ├── mod.zig
               └── interaction.zig      # Hitboxes dinâmicas (Hazards, Moedas, Obstáculos, Triggers)
   ```

---

## 3. Desafios Técnicos e Soluções Implementadas

### A. Adaptação para a Nova API do Compilador Zig `0.17.0-dev`
* **Mudanças na API do Zig 0.17:**
  * `@cImport` foi substituído no compilador por `b.addTranslateC` no `build.zig`. Criamos `src/c_headers.h` e o módulo `raylib_c` via `translate_c.createModule()`.
  * `b.addExecutable` agora exige `root_module: *std.Build.Module` criado com `b.createModule`.
  * Passagem de argumentos de CLI para `zig build run` utiliza `run_cmd.addPassthruArgs()`.
  * `std.ArrayListUnmanaged` e `std.AutoHashMapUnmanaged` utilizam inicialização explícita `= .empty`.
  * Identificadores como `i0`, `i1`, `i2` são tipos inteiros primitivos em Zig (substituídos por `idx0`, `idx1`, `idx2`).

### B. Seleção Automática da GPU Dedicada no Windows (NVIDIA Optimus)
* **Sintoma:** Em notebooks híbridos (Intel UHD Graphics + NVIDIA GeForce RTX 3060 Laptop GPU), executáveis OpenGL usam a placa integrada Intel por padrão, a menos que o binário exporte símbolos específicos na tabela PE.
* **Armadilha Evitada:** Usar `exe.rdynamic = true` exporta todos os símbolos internos da libc/GLFW e causa conflito com o driver `nvoglv64.dll`.
* **Solução (`src/gpu_optimus.c`):** Um pequeno arquivo C compilado junto ao executável declara:
  ```c
  #if defined(_WIN32)
  __declspec(dllexport) unsigned long NvOptimusEnablement = 0x00000001;
  __declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
  #endif
  ```
  Isso instrui o linker PE a exportar exclusivamente esses dois símbolos, fazendo o driver da NVIDIA ativar automaticamente a **RTX 3060 Laptop GPU**.

### C. Limitador de 60 FPS de Precisão Sub-Milissegundo no Windows
* **Sintoma:** A função `Sleep()` padrão do Windows possui granularidade de ~15.6ms, causando oscilações no tempo de quadro se usada isoladamente.
* **Solução (`src/settings/diagnostics.zig`):**
  * Ativação de `timeBeginPeriod(1)` (via `winmm.lib`) na inicialização para resolução de 1ms no kernel do Windows.
  * Combinação de `WaitTime` até 1.8ms antes do alvo seguida de *busy-wait* com `std.atomic.spinLoopHint()`, resultando em **60.0 FPS cravados (`16.67ms`) com Jitter ($\sigma$) de `0.02ms` e 0 spikes**.

### D. Canvas Retrô Offscreen + FXAA na Resolução Interna + Upscale Nearest
* **Arquitetura de 2 Passes (`src/settings/display.zig`):**
  1. **Passe 1 (`scene_target`):** Renderiza a cena 3D na resolução interna (`INTERNAL_WIDTH × INTERNAL_HEIGHT`) com o shader GLSL 330 de iluminação difusa cartunesca.
  2. **Passe 2 (`canvas_target`):** Aplica o shader GLSL 330 de **FXAA** sobre `scene_target` mantendo a resolução interna.
  3. **Apresentação na Janela:** O `canvas_target` (com filtro `TEXTURE_FILTER_POINT`) é desenhado escalado na janela física com barras pretas (*letterbox/pillarbox*), preservando os pixels retrô nítidos mesmo em monitores 1440p/4K.

### E. Alinhamento da Malha Cônica do Jogador com Quaternions
* **Detalhe Geométrico:** Na Raylib, `GenMeshCone(radius, height, slices)` gera um cone com base em $Y = 0$ e topo em $Y = \text{height}$ ($1.2$), enquanto a física e o cálculo de rotação Quaternion consideram a origem no centro do corpo ($Y \in [-0.6, +0.6]$).
* **Solução (`src/scene/player/player.zig`):** Aplicação de `MatrixTranslate(0.0, -PLAYER_HALF_HEIGHT, 0.0)` pré-multiplicada pela matriz de rotação do Quaternion (`MatrixMultiply(center_offset, rot_mat)`), garantindo que a ponta do cone aponte exatamente para a direção frontal de movimento e incline perfeitamente nas rampas.

---

## 4. Código e Configuração dos Módulos Principais (`_ZIG/`)

### `_ZIG/build.zig`
Compila a Raylib 5.5 em C99 para Windows, Linux e macOS, traduz os cabeçalhos C e configura os steps `zig build run` e `zig build test`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c_headers.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(b.path("vendor/raylib/src"));
    const raylib_c_mod = translate_c.createModule();

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "raylib_c", .module = raylib_c_mod },
        },
    });

    exe_mod.addIncludePath(b.path("vendor/raylib/src"));
    exe_mod.addIncludePath(b.path("vendor/raylib/src/external/glfw/include"));
    // ... Compilação dos arquivos C da Raylib (rcore, rshapes, rtextures, rtext, rmodels, utils, raudio, rglfw)
    // e linkagem das bibliotecas nativas (winmm, gdi32, opengl32, user32, shell32 no Windows)
}
```

---

### `_ZIG/src/settings/display.zig` (Central de Vídeo, Shaders e Canvas Retrô)
> **Como alterar resolução ou filtros:** Edite as constantes no topo de `_ZIG/src/settings/display.zig` ou use variáveis de ambiente (`$env:TEXTURE_FILTERING="anisotropic"`, `$env:TARGET_FPS="60"`).

Principais constantes:
* `INTERNAL_WIDTH: i32 = 854;` / `INTERNAL_HEIGHT: i32 = 480;` (com tabela de presets de 144p a 1080p).
* `DISABLE_MSAA: bool = false;` (ativa 4x MSAA).
* `TEXTURE_FILTERING: TextureFilteringMode = .Pixelated;` (`.Pixelated`, `.Linear`, `.Anisotropic16x`).
* `ENABLE_FXAA: bool = true;` (pós-processamento FXAA na resolução interna).
* `REMOVE_SPECULAR_PHONG: bool = true;` (iluminação cartunesca difusa estilo Nintendo DS).
* `TARGET_FPS: ?f32 = 60.0;` (trava de 60 FPS).

---

### `_ZIG/src/scene/camera/camera.zig` (Câmera Orbital Estilo Lakitu)
* Controles idênticos ao Super Mario 64:
  * Giro orbital horizontal via `Q`/`E` ou `Setas Esquerda/Direita`.
  * Botão `R`: recentraliza instantaneamente atrás da direção em que o jogador olha.
  * Botão Direito do Mouse: órbita livre em `yaw` e `pitch` (limitado entre `-0.05` e `1.1` rad).
  * Roda do Mouse (Scroll): zoom suave entre `6.0` e `30.0` unidades.
  * Perseguição suavizada (`lerp`) tanto para o ponto de foco quanto para a posição da câmera.

---

### `_ZIG/src/scene/player/player.zig` (Física SM64, Movimentação e Stats)
* **Física Horizontal (Plano XZ):** Aceleração progressiva (`15.0`), velocidade máxima (`7.0`), curva com preservação de momentum (`turn_speed = 28.0`), derrapagem rápida em inversões bruscas (`skid_deceleration = 32.0` quando `dot < -0.4`) e atrito gradual ao soltar os controles.
* **Gravidade e Salto Variável (Eixo Y):** Impulso de pulo (`12.0`), gravidade (`30.0`), corte de subida ao soltar `Espaço` (`jump_cut_factor = 0.5`) e controle aéreo (`0.65`).
* **Inclinação na Rampa (`tilt`):** Calcula o ângulo da rampa exclusivamente na direção do olhar do personagem (`tilt_strength = 0.6`, máximo `0.28 rad` / ~16°) e interpola via `Quat.slerp`.
* **Saúde e Eventos:** 8 fatias de vida estilo SM64, contador de moedas, knockback ao sofrer dano e efeito de piscar durante os `1.2s` de invulnerabilidade.

---

### `_ZIG/src/scene/world/collision.zig` (Colisão Determinística + Grade Espacial XZ)
* Classifica todos os triângulos do cenário pela componente $Y$ da normal:
  * **Pisos (`normal.y > 0.5`):** Coordenadas baricêntricas no plano XZ, subida automática de degraus até `STEP_HEIGHT = 0.5` e *snap* ao descer rampas.
  * **Paredes (`|normal.y| <= 0.5`):** Ponto mais próximo no triângulo (algoritmo de Ericson) testado em duas alturas do corpo (`-0.3` joelho e `+0.3` peito), deduplicado por célula e pré-filtrado por AABB.
  * **Tetos (`normal.y < -0.5`):** Bloqueia a cabeça do jogador e zera a velocidade vertical de subida.
* **Grade Espacial Uniforme (`TriangleGrid`):** Células de `4.0 × 4.0` unidades no plano XZ com lista `large_triangles` para triângulos que cobrem mais de 64 células. Possui testes unitários validados via `zig build test`.

---

## 5. Comandos de Uso Rápido

No terminal PowerShell, dentro de `E:\_CODES\3D-Game\_ZIG`:

```powershell
# Compilar e executar em modo desenvolvimento
cd E:\_CODES\3D-Game\_ZIG
zig build run

# Executar os testes unitários da grade espacial de colisão
zig build test

# Compilar binário final de produção com otimização máxima
zig build -Doptimize=ReleaseFast

# Testar com filtragem Anisotrópica 16x via variável de ambiente
$env:TEXTURE_FILTERING="anisotropic"; zig build run
```

---

## 6. Status dos Objetivos e Próximos Passos

1. **[CONCLUÍDO] Física de Movimentação Horizontal e Inércia (Passo 1)**
2. **[CONCLUÍDO] Gravidade, Pulo Variável e Estado de Chão (Passo 2)**
3. **[CONCLUÍDO] Câmera Seguidora Orbital Estilo Lakitu (Passo 3)**
4. **[CONCLUÍDO] Colisão Determinística Estática com Grade Espacial XZ (Passo 4)**
5. **[CONCLUÍDO] Estética Nintendo DS, Canvas Offscreen, MSAA 4x, FXAA e Anisotrópico 16x (Passo 5)**
6. **[CONCLUÍDO] Diagnóstico de Hardware, Seleção Automática da RTX 3060 e Trava de 60 FPS (Passo 6)**
7. **[CONCLUÍDO] Migração Completa para Zig 0.17 + Raylib 5.5 em `_ZIG/` (Passo 7):**
   * Todos os sistemas portados, testados e rodando a **60.0 FPS cravados (`16.67ms`), Jitter de `0.02ms` e 0 spikes** na **NVIDIA GeForce RTX 3060 Laptop GPU**.
8. **[PRÓXIMO CAPÍTULO] Modelagem do Personagem e Sistema de Animações (Passo 8):**
   * Modelagem, rig (esqueleto) e animações (Idle, Walk, Run, Jump, Skid) no Blender exportados em `.glb`.
   * Carregamento e reprodução de animações esqueléticas na Raylib (`LoadModelAnimations` e `UpdateModelAnimation`) sincronizadas com a velocidade e o estado do `PlayerController` em `_ZIG/src/scene/player/player.zig`.
   * Criação de novas fases e posicionamento de moedas, obstáculos e inimigos utilizando `InteractionWorld` (`_ZIG/src/scene/objects/interaction.zig`).
