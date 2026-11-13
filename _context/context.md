# Documento de Contexto: Plataforma 3D Retrô (Zig + Raylib 5.5)

> **Finalidade deste documento:** Servir como fonte única da verdade sobre a arquitetura, decisões técnicas, problemas solucionados e estado atual do código para permitir que o desenvolvimento continue em qualquer computador sem perda de contexto.
> *(Para navegação rápida de código pelo agente, consulte também o [`GEMINI.md`](file:///e:/_CODES/3D-Game/GEMINI.md) na raiz do projeto).*

---

## 1. Visão Geral e Direção Artística

* **Conceito:** Jogo de plataforma 3D retrô inspirado na estética e na física de *Super Mario 64* (especificamente a direção de arte e estilo do port para Nintendo DS: *Super Mario 64 DS*).
* **Direção Visual:**
  * **Renderização Interna em Canvas Offscreen:** O mundo 3D é desenhado internamente em um *Framebuffer Offscreen* (`RenderTexture2D`, padrão `1280 × 720` em 16:9 widescreen, configurável para presets retrô como `854 × 480` ou `256 × 144`), e escalado para a janela física via **Bilinear (`TEXTURE_FILTER_BILINEAR`)** ou **Nearest-Neighbor (`TEXTURE_FILTER_POINT`)** com preservação de proporção (*Letterbox / Pillarbox*).
  * **Filtragem de Texturas Configurável com Tiling:**
    * **`CrispPixelAA` (Padrão Recomendado):** Shader analítico de sub-pixel que mantém os pixels **100% nítidos, vívidos e quadrados de perto** (abaixo de `CRISP_DIST_NEAR = 8.0`), realiza uma transição gradual (`smoothstep`) entre `8.0` e `CRISP_DIST_FAR = 16.5`, e aplica filtragem **Anisotrópica 16x** (ou Linear) à distância para eliminar totalmente o efeito Moiré e cintilação (*shimmering*) em ângulos rasantes.
    * **`Pixelated`:** Nearest-Neighbor puro (estilo clássico com ruído em perspectiva).
    * **`Linear` / `Anisotropic16x`:** Filtros clássicos com mipmaps em todas as distâncias.
  * **Iluminação Cartunesca Pura (Shader GLSL 330 Sem Phong/Specular):** Shader customizado de iluminação direcional solar `(10, 20, 10)` com preenchimento de luz ambiente viva (`0.58 + 0.42 * NdotL`), eliminando brilhos especulares plásticos e suportando malhas de face dupla (`doubleSided`).
  * **Anti-Aliasing Geométrico Offscreen (MSAA 4x) + FXAA Opcional:** Framebuffer multisample dedicado (`glRenderbufferStorageMultisample` 4x resolvido via `glBlitFramebuffer`) para suavizar as arestas poligonais 3D diretamente no canvas offscreen, além de um passe opcional de pós-processamento **FXAA**.
* **Paradigma de Desenvolvimento:** Baixo nível, código nativo compilado em **Zig (`0.17.0-dev`)** com **Raylib 5.5 (OpenGL 3.3 Core)** compilada diretamente do código-fonte C via `zig cc`, gerando um binário autocontido, multiplataforma e ultraleve (~4.6 MB em Debug).

---

## 2. Decisões Arquiteturais e Estrutura do Projeto

1. **Stack Central:** **Zig (`0.17.0-dev`) + Raylib 5.5 + Blender (`.glb` / glTF 2.0)**.
   * **Compilação C Integrada (`zig cc`):** O código-fonte oficial em C99 da Raylib 5.5 (`vendor/raylib/src`) é compilado diretamente pelo sistema de build do Zig ([`build.zig`](file:///e:/_CODES/3D-Game/build.zig)), sem depender de bibliotecas pré-compiladas externas ou wrappers de terceiros.
   * **Pipeline de Assets:** O Blender exporta cenários e modelos diretamente em formato `.glb` (glTF 2.0 binário com texturas PNG embutidas), carregados nativamente via `LoadModel` da Raylib (`cgltf`).

2. **Hierarquia Modular de Responsabilidades (`src/`):**
   ```text
   3D-Game/
   ├── GEMINI.md                        # Mapa cirúrgico de símbolos/linhas carregado automaticamente pelo agente
   ├── build.zig                        # Script de build (Zig 0.17) + compilação C da Raylib 5.5
   ├── build.zig.zon                    # Manifesto do pacote Zig
   ├── assets/                          # Modelos .glb (Scene.glb), texturas (tile.png) e fontes (fonts/arial.ttf)
   ├── vendor/raylib/src/               # Código-fonte C99 oficial da Raylib 5.5 e GLFW
   └── src/
       ├── main.zig                     # Ponto de entrada e loop principal (Atalhos F1-F11 / Update / Render)
       ├── c_headers.h                  # Header unificado traduzido via addTranslateC
       ├── gpu_optimus.c                # Exportação PE (NvOptimusEnablement / AMD PowerXpress)
       ├── rl.zig                       # Ponte tipada para Raylib, RLGL e Raymath
       ├── math.zig                     # Matemática 3D (Vec2, Vec3, Quat com slerp)
       ├── settings/
       │   ├── mod.zig
       │   ├── display.zig              # Resolução, Canvas Offscreen, MSAA 4x FBO, Shaders GLSL, Filtros e HUD
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

### A. Adaptação para a API do Compilador Zig `0.17.0-dev`
* **`b.addTranslateC` no `build.zig`:** Traduz `src/c_headers.h` e cria o módulo `raylib_c` via `translate_c.createModule()`.
* **`b.addExecutable`:** Utiliza `root_module: *std.Build.Module` criado com `b.createModule`.
* **Coleções Não-Gerenciadas:** `std.ArrayListUnmanaged` e `std.AutoHashMapUnmanaged` utilizam inicialização explícita `= .empty`.
* **Formatação Zero-Terminada para C:** Função auxiliar `printZ` em `DisplaySystem` formata fatias `[:0]const u8` compatíveis com chamadas C da Raylib.

### B. Seleção Automática da GPU Dedicada no Windows (NVIDIA Optimus)
* **Sintoma:** Em notebooks híbridos (Intel UHD Graphics + NVIDIA GeForce RTX 3060 Laptop GPU), executáveis OpenGL usam a placa integrada Intel por padrão, a menos que o binário exporte símbolos específicos na tabela PE.
* **Armadilha Evitada:** Usar `exe.rdynamic = true` exporta todos os símbolos internos da libc/GLFW e causa conflito com o driver `nvoglv64.dll`.
* **Solução ([`src/gpu_optimus.c`](file:///e:/_CODES/3D-Game/src/gpu_optimus.c)):** Pequeno arquivo C compilado junto ao executável que exporta exclusivamente `NvOptimusEnablement = 0x00000001` e `AmdPowerXpressRequestHighPerformance = 1`, fazendo o driver da NVIDIA ativar automaticamente a **RTX 3060 Laptop GPU**.

### C. Limitador de FPS de Precisão Sub-Milissegundo no Windows
* **Solução ([`src/settings/diagnostics.zig`](file:///e:/_CODES/3D-Game/src/settings/diagnostics.zig)):**
  * Ativação de `timeBeginPeriod(1)` (via `winmm.lib`) na inicialização para resolução de 1ms no kernel do Windows.
  * Combinação de `WaitTime` até 1.8ms antes do alvo seguida de *busy-wait* com `std.atomic.spinLoopHint()`, garantindo **Jitter ($\sigma$) de `0.02ms` e 0 spikes** quando o FPS Cap está ativo.

### D. Canvas Offscreen com MSAA 4x Dedicado + CrispPixelAA + HUD Vetorial
* **Pipeline de Renderização ([`src/settings/display.zig`](file:///e:/_CODES/3D-Game/src/settings/display.zig)):**
  1. **Passe 1 (MSAA 4x Offscreen ➔ `scene_target`):** Como `FLAG_MSAA_4X_HINT` do GLFW só afeta o backbuffer principal da janela, `DisplaySystem` cria um FBO multisample OpenGL dedicado (`MsaaTarget` com `GL_RGBA8` + `GL_DEPTH_COMPONENT24` de 4 amostras) e faz o resolve via `glBlitFramebuffer` para `scene_target` ao final da cena 3D.
  2. **Passe 2 (`canvas_target` / FXAA Opcional):** Se `ENABLE_FXAA` estiver ativo, aplica o shader GLSL 330 de FXAA na resolução interna.
  3. **Apresentação na Janela:** O canvas final é escalado para a janela física usando `CANVAS_SCALING` (`.Bilinear` ou `.Nearest`) com barras pretas (*letterbox/pillarbox*).
  4. **HUD / OSD Vetorial:** Renderizado diretamente na resolução nativa da janela com a fonte TrueType `assets/fonts/arial.ttf` carregada em 48px com filtro bilinear.

### E. Alinhamento da Malha Cônica do Jogador com Quaternions
* **Solução ([`src/scene/player/player.zig`](file:///e:/_CODES/3D-Game/src/scene/player/player.zig)):** Aplicação de `MatrixTranslate(0.0, -PLAYER_HALF_HEIGHT, 0.0)` pré-multiplicada pela matriz de rotação do Quaternion (`MatrixMultiply(center_offset, rot_mat)`), garantindo que a ponta do cone aponte exatamente para a direção frontal de movimento e incline perfeitamente nas rampas.

---

## 4. Configurações Padrão Atuais ([`src/settings/display.zig`](file:///e:/_CODES/3D-Game/src/settings/display.zig))

* `SHOW_DISPLAY_OVERLAY: bool = true;` (Exibe o HUD de telemetria e atalhos no canto superior esquerdo).
* `OSD_FONT_SIZE: i32 = 20;` (Fonte Arial TrueType nítida).
* `INTERNAL_WIDTH: i32 = 1280;` / `INTERNAL_HEIGHT: i32 = 720;`
* `CANVAS_SCALING: CanvasScalingMode = .Bilinear;` (`.Nearest` ou `.Bilinear`).
* `DISABLE_MSAA: bool = false;` (4x MSAA offscreen ativo nas bordas poligonais).
* `TEXTURE_FILTERING: TextureFilteringMode = .CrispPixelAA;`
* `CRISP_DIST_NEAR: f32 = 8.0;` / `CRISP_DIST_FAR: f32 = 16.5;`
* `CRISP_FALLBACK: CrispFallbackFilter = .Anisotropic16x;`
* `ENABLE_FXAA: bool = false;`
* `ENABLE_VSYNC: bool = true;`
* `TARGET_FPS: ?f32 = null;` (Taxa de quadros livre acompanhando o VSync/monitor, alternável via `F5`).
* `REMOVE_SPECULAR_PHONG: bool = true;`
* **🎮 Atalhos em Tempo Real Durante o Jogo:**
  * `[F1]` Alternar exibição do HUD/OSD (`ON` ⮂ `OFF`)
  * `[F2]` Ciclar filtragem de textura (`CrispPixelAA` ➔ `Pixelated` ➔ `Linear` ➔ `Anisotropic16x`)
  * `[F3]` Alternar escalonamento do canvas (`Nearest` ⮂ `Bilinear`)
  * `[F4]` Alternar FXAA (`ON` ⮂ `OFF`)
  * `[F5]` Alternar trava de FPS (`60 FPS` ⮂ `Livre`)
  * `[F6/F7]` Ajustar distância `Near` (`-2.0` / `+2.0` unidades)
  * `[F8/F9]` Ajustar distância `Far` (`-2.0` / `+2.0` unidades)
  * `[F10]` Alternar fallback distante (`Anisotropic16x` ⮂ `Linear`)
  * `[F11]` Alternar MSAA 4x offscreen (`ON` ⮂ `OFF`)

---

## 5. Comandos de Uso Rápido

No terminal PowerShell, na raiz `e:\_CODES\3D-Game`:

```powershell
# Compilar e executar em modo desenvolvimento
zig build run

# Compilar sem executar
zig build

# Executar os testes unitários da grade espacial de colisão
zig build test

# Compilar binário final de produção com otimização máxima
zig build -Doptimize=ReleaseFast
```

---

## 6. Status dos Objetivos e Próximos Passos

1. **[CONCLUÍDO] Física de Movimentação Horizontal, Inércia e Skid (`player.zig`)**
2. **[CONCLUÍDO] Gravidade, Pulo Variável e Inclinação em Rampas (`player.zig`)**
3. **[CONCLUÍDO] Câmera Seguidora Orbital Estilo Lakitu (`camera.zig`)**
4. **[CONCLUÍDO] Colisão Determinística Estática com Grade Espacial XZ (`collision.zig`)**
5. **[CONCLUÍDO] Estética Nintendo DS, Canvas Offscreen, MSAA 4x Offscreen, CrispPixelAA Near/Far e HUD Interativo (`display.zig`)**
6. **[CONCLUÍDO] Diagnóstico de Hardware, Seleção Automática da RTX 3060 e Controle de FPS/VSync (`diagnostics.zig`)**
7. **[PRÓXIMO PASSO — AGUARDANDO O USUÁRIO] Personagem simples e pipeline de animação:**
   * O modelo [`assets/person/esqueleto.glb`](file:///e:/_CODES/3D-Game/assets/person/esqueleto.glb) e sua integração em [`src/scene/player/player.zig`](file:///e:/_CODES/3D-Game/src/scene/player/player.zig) são **experimentais**: o usuário observou animação incorreta. Não tratar a integração como validada; preservar o GLB antigo e as alterações existentes.
   * O usuário criará posteriormente, no **Blender 5.2**, um protótipo de blocos simples e exportará para `assets/person/personagem_teste.glb` (caminho planejado; o arquivo ainda não existe). Guardar o `.blend` original; não substituir o GLB antigo.
   * **Contrato proposto:** um objeto de malha `CharacterMesh`, sem acessórios ou texturas; uma armature `CharacterRig` com cinco ossos (`Body`, `Arm.L`, `Arm.R`, `Leg.L`, `Leg.R`); um osso por vértice com peso 1; altura aproximada de 1,2 unidade, origem entre os pés, vertical +Z e frente +Y no Blender. Manter transforms dos objetos limpos e evitar IK, constraints e ossos auxiliares no primeiro teste.
   * **Ações:** somente `Idle` e `Walk`, com nomes curtos e distintos, em ciclo e sem deslocamento da raiz; movimento do jogador continua controlado pela física. O plano é usar 24 fps no Blender e keyframes amostrados.
   * **Exportação planejada:** glTF Binary `.glb`, apenas objetos selecionados, `+Y Up`, skinning e animações habilitados, modo de animação `Actions`, amostragem em cada quadro e reset de pose entre ações quando disponíveis; sem compressão Draco/Meshopt. Conferir os nomes das opções no Blender 5.2 e reimportar o GLB para verificar as duas ações.
   * **Validação antes da integração:** inspecionar malhas, hierarquia, pesos, transforms e nomes no GLB; testar visualmente pose, orientação, escala e as duas animações isoladas; verificar troca `Idle`/`Walk` e só então integrar movimento, colisão e câmera. Não reaproveitar cegamente índices de clipes ou compensações específicas do modelo antigo.
   * **Raylib:** o shader padrão e o shader de iluminação atual não calculam skinning de ossos. Começar avaliando skinning CPU com `UpdateModelAnimation` para a malha rigada; a compatibilidade do arquivo e a correção visual precisam ser testadas, não presumidas.
8. **[POSTERIOR]** Animações de pulo/ataque, novas fases e posicionamento de moedas, obstáculos e inimigos utilizando `InteractionWorld` ([`src/scene/objects/interaction.zig`](file:///e:/_CODES/3D-Game/src/scene/objects/interaction.zig)).
