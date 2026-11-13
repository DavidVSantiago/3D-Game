# Mapa Cirúrgico do Projeto & Protocolo de Velocidade (3D-Game)

> **Propósito:** Este arquivo é carregado automaticamente pelo Antigravity em todas as conversas. Consulte este mapa para ir **direto ao arquivo e intervalo de linhas exato**, sem fazer buscas exploratórias ou ler arquivos inteiros desnecessariamente.

---

## ⚡ 1. Regras de Execução Rápida para o Agente

1. **Idioma e Links:** Responda sempre em **Português** de forma concisa e objetiva, usando links clicáveis (`file:///e:/_CODES/3D-Game/...`).
2. **Leitura Cirúrgica (`read_file`):** **Nunca** leia arquivos grandes inteiros quando precisar alterar apenas uma seção. Use sempre `StartLine` e `EndLine` guiando-se pelo Mapa da Seção 2.
3. **Sem Buscas Redundantes:** A estrutura completa do projeto está mapeada na Seção 2. Não execute `Get-ChildItem`, `find` ou buscas globais para descobrir onde ficam módulos ou assets já listados aqui.
4. **Compilação Enxuta (`run_command`):**
   - Faça todas as edições de código primeiro e compile **apenas uma vez** ao final:
     `Stop-Process -Name "retro_platformer" -Force -ErrorAction SilentlyContinue; zig build`
   - Só execute `zig build test` quando alterar lógica matemática ou de colisão (`src/math.zig` ou `src/scene/world/collision.zig`). Para ajustes visuais, shaders, HUD, câmera ou constantes, `zig build` basta.
5. **Manutenção Contínua do Mapa (`AGENTS.md` e `_context/context.md`):**
   - Sempre que criar novos arquivos, mover módulos, deletar arquivos ou alterar significativamente a quantidade de linhas ou funções de um arquivo existente, **atualize imediatamente este arquivo (`AGENTS.md`)** na Seção 2 com os novos caminhos e intervalos de linha.
   - Quando concluir um novo marco arquitetural (ex.: sistema de animações, novos objetos interativos ou fases), atualize também o resumo em [`_context/context.md`](file:///e:/_CODES/3D-Game/_context/context.md).

---

## 🗺️ 2. Mapa de Arquivos, Símbolos e Intervalos de Linhas

### Raiz, Build e Assets (`e:/_CODES/3D-Game/`)
- [`build.zig`](file:///e:/_CODES/3D-Game/build.zig) (135 linhas): Build script para **Zig `0.17.0-dev`**.
  - `L1–L45`: Target, optimize e tradução de `src/c_headers.h` via `b.addTranslateC` (`raylib_c`).
  - `L46–L108`: Compilação C99 da Raylib 5.5 (`vendor/raylib/src`) + `src/gpu_optimus.c` e link com `winmm`, `gdi32`, `opengl32`.
  - `L109–L135`: Steps `run` e `test` (`zig build run`, `zig build test`).
- [`build.zig.zon`](file:///e:/_CODES/3D-Game/build.zig.zon) (10 linhas): Manifesto do pacote Zig (`retro_platformer`).
- [`_context/context.md`](file:///e:/_CODES/3D-Game/_context/context.md): Documentação arquitetural detalhada, decisões técnicas e roadmap do projeto; consulte a seção 6 para o próximo passo do personagem.
- **Assets (`assets/`):**
  - `assets/Scene.glb`: Cenário 3D principal exportado do Blender (glTF 2.0 binário).
  - `assets/person/esqueleto.glb`: Modelo experimental atual, com animação problemática; preservar o arquivo e não considerá-lo validado.
  - `assets/person/personagem_teste.glb`: Caminho proposto para o novo protótipo; ainda não existe e será criado pelo usuário no Blender 5.2.
  - `assets/tile.png`: Textura de piso em pixel art usada pelo fallback procedural.
  - `assets/fonts/arial.ttf`: Fonte TrueType vetorial usada pelo HUD/OSD em alta resolução.

### Núcleo e Loop Principal (`src/`)
- [`src/main.zig`](file:///e:/_CODES/3D-Game/src/main.zig) (181 linhas):
  - `L17–L75`: Inicialização da janela, `DiagnosticsSystem`, `DisplaySystem`, `LakituCamera`, `Player`, `TerrainManager`, `InteractionWorld`.
  - `L76–L150`: Loop principal — atalhos em tempo real (`F1`–`F12`, tela cheia em F12), `player.updateMovement`, `player.updateAnimation`, `interaction_world.update`, `camera.update`.
  - `L151–L180`: Renderização 3D offscreen (`begin3DCanvas` ➔ `terrain` / `interaction` / `player` ➔ `end3DCanvas`), apresentação (`presentCanvas`), HUD (`drawOverlay`) e limitador de FPS (`endFrameAndPace`).
- [`src/rl.zig`](file:///e:/_CODES/3D-Game/src/rl.zig) (24 linhas): Importação de `@import("raylib_c")` (`rl.c`) e conversores `toRlVec3`, `fromRlVec3`, `quatToMatrix`, `getEnv`.
- [`src/math.zig`](file:///e:/_CODES/3D-Game/src/math.zig) (226 linhas):
  - `L3–L17`: `Vec2`
  - `L18–L109`: `Vec3` (`add`, `sub`, `scale`, `dot`, `cross`, `length`, `normalizeOrZero`, `lerp`)
  - `L110–L226`: `Quat` (`fromAxisAngle`, `fromRotationY`, `mul`, `slerp`, `mulVec3`)
- [`src/gpu_optimus.c`](file:///e:/_CODES/3D-Game/src/gpu_optimus.c) (4 linhas): Exporta `NvOptimusEnablement` e `AmdPowerXpressRequestHighPerformance` para ativar a GPU dedicada no Windows.
- [`src/c_headers.h`](file:///e:/_CODES/3D-Game/src/c_headers.h) (9 linhas): Headers C da Raylib (`raylib.h`, `rlgl.h`, `raymath.h`).

### Configurações de Vídeo, Shaders, MSAA e HUD (`src/settings/`)
- [`src/settings/mod.zig`](file:///e:/_CODES/3D-Game/src/settings/mod.zig) (2 linhas): Reexporta `display.zig` e `diagnostics.zig`.
- [`src/settings/display.zig`](file:///e:/_CODES/3D-Game/src/settings/display.zig) (1029 linhas):
  - `L1–L47`: Resolução interna (`INTERNAL_WIDTH = 1280`, `INTERNAL_HEIGHT = 720`), janela (`WINDOW_WIDTH`, `WINDOW_HEIGHT`), cores e `DISABLE_MSAA = false`.
  - `L48–L108`: Modos e constantes padrão:
    - `CANVAS_SCALING = .Bilinear` (`CanvasScalingMode`: `.Nearest`, `.Bilinear`)
    - `TEXTURE_FILTERING = .CrispPixelAA` (`TextureFilteringMode`: `.CrispPixelAA`, `.Pixelated`, `.Linear`, `.Anisotropic16x`)
    - `ENABLE_FXAA = false`, `REMOVE_SPECULAR_PHONG = true`, `GPU_MODE_PREFERENCE = "high"`, `ENABLE_VSYNC = true`, `TARGET_FPS = null`
  - `L110–L134`: Transição Crisp Pixel Art por distância (`CRISP_DIST_NEAR = 8.0`, `CRISP_DIST_FAR = 16.5`, `CRISP_FALLBACK = .Anisotropic16x`).
  - `L136–L260`: Constantes do HUD (`SHOW_DISPLAY_OVERLAY = true`, `OSD_FONT_SIZE = 20`) e getters com leitura de variáveis de ambiente (`getShowDisplayOverlay`, `getCrispDistNear`, `getCrispDistFar`, `getCrispFallbackFilter`, `getCanvasScalingMode`, `getTextureFilteringMode`).
  - `L265–L306`: `configureModelTextureWithFallback` e `configureModelTexture` (mipmaps; base trilinear antes da anisotropia, inclusive no CrispPixelAA).
  - `L312–L428`: Shaders GLSL 330 embutidos (`LIGHTING_VS`, `LIGHTING_FS` com `CrispPixelAA` analítico + distância Near/Far, e `FXAA_FS`).
  - `L440–L510`: OpenGL FBO Multisample 4x (`GlFns`, `loadGlFns`, `MsaaTarget`) + `OverlayInfo`.
  - `L511–L693`: `DisplaySystem`, `init`, `deinit`, FBOs e fonte TrueType com ASCII + glifos portugueses explícitos; diagnóstico do uniforme `useCrispPixelAA`.
  - `L684–L756`: Controles em tempo real e `applyTextureFilteringMode` (sincroniza o uniforme ao alternar com F2).
  - `L758–L1029`: `setCrispThresholds`, `begin3DCanvas`, HUD (`drawOverlay` com separador e grade de atalhos 3×3, estado de tela cheia/F12, + `printZ`) e `end3DCanvasAndPresent`.
- [`src/settings/diagnostics.zig`](file:///e:/_CODES/3D-Game/src/settings/diagnostics.zig) (295 linhas):
  - `L15–L98`: `GpuSelectionMode` e `DiagnosticRenderConfig.loadConfiguration`.
  - `L99–L295`: `DiagnosticsSystem` (detecção OpenGL da GPU ativa, `toggleFpsCap` para `[F5]`, telemetria de frame time/jitter e limitador sub-milissegundo `endFrameAndPace`).

### Cena, Câmera, Jogador, Mundo e Colisão (`src/scene/`)
- Agregadores de módulo: [`src/scene/mod.zig`](file:///e:/_CODES/3D-Game/src/scene/mod.zig), [`src/scene/camera/mod.zig`](file:///e:/_CODES/3D-Game/src/scene/camera/mod.zig), [`src/scene/player/mod.zig`](file:///e:/_CODES/3D-Game/src/scene/player/mod.zig), [`src/scene/world/mod.zig`](file:///e:/_CODES/3D-Game/src/scene/world/mod.zig), [`src/scene/objects/mod.zig`](file:///e:/_CODES/3D-Game/src/scene/objects/mod.zig).
- [`src/scene/camera/camera.zig`](file:///e:/_CODES/3D-Game/src/scene/camera/camera.zig) (102 linhas): `LakituCamera` (órbita `Q`/`E`/Setas/Mouse Direito, zoom no scroll, recentralizar com `R`, interpolação suave `lerp`).
- [`src/scene/player/player.zig`](file:///e:/_CODES/3D-Game/src/scene/player/player.zig) (~445 linhas):
  - `L1–L90`: `PlayerController` (constantes de física estilo SM64: aceleração, inércia, skid, pulo variável, gravidade, tilt na rampa) e `PlayerStats` (vida, moedas, invulnerabilidade).
  - `L76–L160`: `Player.init`, `deinit`, troca de animação `Idle`/`Walk` e skinning CPU do modelo esquelético `assets/person/esqueleto.glb`.
  - `L161–L380`: Física completa do `Player.updateMovement` (inércia, gravidade, salto e colisões).
  - `L381–L445`: Interações, estado visual e `Player.draw` do modelo animado com escala 0.8.
  - **Estado experimental:** a animação do `esqueleto.glb` apresentou problemas; não reutilizar índices e compensações específicos do asset como padrão para o novo modelo.
- [`src/scene/world/terrain.zig`](file:///e:/_CODES/3D-Game/src/scene/world/terrain.zig) (151 linhas): `TerrainManager` (carrega `assets/Scene.glb` ou gera cenário procedural fallback, extrai triângulos de colisão, aplica shader de iluminação e `reapplyTextureFilter`).
- [`src/scene/world/collision.zig`](file:///e:/_CODES/3D-Game/src/scene/world/collision.zig) (477 linhas):
  - `L1–L190`: `Triangle`, classificação Piso/Parede/Teto pela normal $Y$ e `TriangleGrid` (grade espacial uniforme $4.0 \times 4.0$ no plano XZ).
  - `L191–L365`: `LevelCollision` (`findFloor`, `resolveHorizontalCollisions`, `resolveCeilingCollision`).
  - `L366–L477`: Testes unitários da colisão e grade espacial (`zig build test`).
- [`src/scene/objects/interaction.zig`](file:///e:/_CODES/3D-Game/src/scene/objects/interaction.zig) (155 linhas): `InteractionWorld` (hitboxes cilíndricas/esféricas para moedas, perigos/dano, obstáculos sólidos e zonas de gatilho).

### Próximo passo: protótipo de personagem
- Aguardar o usuário criar no **Blender 5.2** um personagem GLB simples: uma malha, uma armature com cinco ossos, pesos rígidos e ações `Idle`/`Walk` no lugar. O contrato e a exportação estão detalhados na seção 6 de [`_context/context.md`](file:///e:/_CODES/3D-Game/_context/context.md).
- Inspecionar o GLB e testar pose, orientação e as duas animações isoladamente antes de integrá-lo à física e à câmera. Preservar o asset antigo; pulo, ataque e novas fases ficam para depois.

---

## 🛠️ 3. Convenções de Código e Armadilhas do Zig `0.17.0-dev` + Raylib 5.5

Para acertar a compilação de primeira sem ciclos extras de erro/correção, siga sempre estas regras da nossa stack:

1. **Proibido `var` não mutado:** O Zig `0.17.0-dev` emite erro fatal (`local variable is never mutated`) se uma variável local não sofrer mutação. Use sempre `const` por padrão.
2. **Formatação de Strings Zero-Terminadas para C (`[:0]const u8`):**
   - `std.fmt.bufPrintZ` **não existe** no Zig `0.17.0-dev`.
   - Use `DisplaySystem.printZ(&buf, fmt, args)` (definido em `src/settings/display.zig`) ou faça `const s = std.fmt.bufPrint(buf[0 .. buf.len - 1], fmt, args) catch ...; buf[s.len] = 0; return buf[0..s.len :0];`.
3. **Coleções Unmanaged (`std.ArrayListUnmanaged` / `std.AutoHashMapUnmanaged`):**
   - Inicialize com `= .empty` e passe o `allocator` explicitamente nos métodos (`list.append(allocator, item)`, `list.deinit(allocator)`).
4. **Carregamento de Fontes TrueType na Raylib (`LoadFontEx`):**
   - Passe sempre `null, 0` nos parâmetros `codepoints` e `codepointCount` (ex.: `rl.c.LoadFontEx(path, 48, null, 0)`) para carregar o conjunto ASCII padrão sem falha.
5. **MSAA Offscreen e NVIDIA Optimus:**
   - A cena 3D é desenhada em FBO offscreen (`RenderTexture2D`), portanto `FLAG_MSAA_4X_HINT` da janela não afeta o canvas 3D; o MSAA 4x é gerenciado pelo `MsaaTarget` (`glRenderbufferStorageMultisample` + `glBlitFramebuffer`) em `src/settings/display.zig`.
   - Nunca ative `exe.rdynamic = true` no `build.zig` (causa conflito com `nvoglv64.dll`). A seleção da GPU NVIDIA dedicada é garantida exclusivamente por `src/gpu_optimus.c`.
