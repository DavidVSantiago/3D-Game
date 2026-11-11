const std = @import("std");
const rl = @import("../../rl.zig");
const math = @import("../../math.zig");
const Vec3 = math.Vec3;
const Quat = math.Quat;
const collision_mod = @import("../world/collision.zig");
const LevelCollision = collision_mod.LevelCollision;
const interaction_mod = @import("../objects/interaction.zig");
const InteractionWorld = interaction_mod.InteractionWorld;
const LakituCamera = @import("../camera/camera.zig").LakituCamera;
const display = @import("../../settings/display.zig");

// 📏 Dimensões do corpo do jogador (cone de 1.2 de altura e raio 0.5, origem no centro)
pub const PLAYER_HALF_HEIGHT: f32 = 0.6;
pub const PLAYER_RADIUS: f32 = 0.5;
pub const STEP_HEIGHT: f32 = 0.5; // Maior degrau que o jogador sobe sem pular
pub const VOID_Y: f32 = -30.0; // Abaixo disso o jogador reaparece
pub const SPAWN_POSITION: Vec3 = Vec3.new(0.0, 10.0, 0.0);

// ❤️ Estatísticas e estado de saúde do jogador
pub const PlayerStats = struct {
    health: u32 = 8, // 8 fatias de vida estilo Super Mario 64
    max_health: u32 = 8,
    coins: u32 = 0,
    invulnerability_timer: f32 = 0.0,
};

// ⚙️ Componente com todos os dados e parâmetros de física do personagem
pub const PlayerController = struct {
    // 🏎️ Física horizontal (Plano XZ)
    velocity: Vec3 = Vec3.ZERO, // Velocidade vetorial total (X, Y, Z)
    max_speed: f32 = 7.0, // Velocidade máxima horizontal de corrida
    acceleration: f32 = 15.0, // Taxa de aceleração horizontal no chão
    deceleration: f32 = 20.0, // Desaceleração por atrito quando solta os controles
    turn_speed: f32 = 28.0, // Rapidez com que a inércia faz a curva no chão
    skid_deceleration: f32 = 32.0, // Desaceleração rápida ao inverter bruscamente a direção

    // 🦘 Gravidade e Salto (Eixo Y)
    is_grounded: bool = false, // Indica se o personagem está em contato com o solo
    gravity: f32 = 30.0, // Aceleração gravitacional contínua
    jump_impulse: f32 = 12.0, // Impulso vertical instantâneo do salto
    terminal_velocity: f32 = -35.0, // Velocidade máxima de queda livre
    air_control_factor: f32 = 0.65, // Eficiência de movimentação e curva no ar (0.0 a 1.0)
    jump_cut_factor: f32 = 0.5, // Multiplicador ao soltar o botão de salto prematuramente

    // 🎭 Orientação visual e inclinação do corpo no terreno
    facing_yaw: f32 = 0.0, // Direção para onde o personagem olha (rotação em Y)
    tilt: Quat = Quat.IDENTITY, // Inclinação atual (suavizada) do corpo
    tilt_strength: f32 = 0.6, // Fração da inclinação real do terreno aplicada ao corpo (0.0 a 1.0)
    max_tilt_angle: f32 = 0.28, // Limite superior da inclinação em radianos (~16°)
    tilt_smoothing: f32 = 10.0, // Rapidez da transição da inclinação
};

// 🏃 Entidade completa do Jogador (Malha 3D + Transform + Controller + Stats)
pub const Player = struct {
    position: Vec3 = SPAWN_POSITION,
    rotation: Quat = Quat.fromRotationX(-std.math.pi * 0.5),
    controller: PlayerController = .{},
    stats: PlayerStats = .{},
    visible: bool = true,
    model: rl.c.Model,

    pub fn init(disp: *const display.DisplaySystem) Player {
        const cone_mesh = rl.c.GenMeshCone(PLAYER_RADIUS, PLAYER_HALF_HEIGHT * 2.0, 24);
        var model = rl.c.LoadModelFromMesh(cone_mesh);
        if (display.REMOVE_SPECULAR_PHONG) {
            model.materials[0].shader = disp.lighting_shader;
        }
        // Cor vermelha vibrante estilo Nintendo DS: srgb(0.95, 0.12, 0.12)
        model.materials[0].maps[rl.c.MATERIAL_MAP_DIFFUSE].color = .{ .r = 242, .g = 31, .b = 31, .a = 255 };

        return .{
            .model = model,
        };
    }

    pub fn deinit(self: *Player) void {
        rl.c.UnloadModel(self.model);
    }

    // 🎮 Sistema integrado de física: inércia horizontal, gravidade, salto, atrito e colisão
    pub fn updateMovement(
        self: *Player,
        raw_dt: f32,
        camera: *const LakituCamera,
        collision: *const LevelCollision,
    ) void {
        if (raw_dt <= 0.0) return;
        // Aguarda a colisão do nível ser construída antes de aplicar a física (evita cair no vazio)
        if (!collision.ready) return;

        // Evita saltos enormes no primeiro quadro após carregamento
        const dt = @min(raw_dt, 1.0 / 20.0);
        var controller = &self.controller;

        // 1. Vetores direcionais da câmera projetados no plano horizontal (XZ)
        var forward = camera.forward();
        var right = camera.right();
        forward.y = 0.0;
        right.y = 0.0;
        forward = forward.normalizeOrZero();
        right = right.normalizeOrZero();

        // 2. Mapeamento dos comandos de direção (WASD)
        var input_dir = Vec3.ZERO;
        if (rl.c.IsKeyDown(rl.c.KEY_W)) input_dir = input_dir.add(forward);
        if (rl.c.IsKeyDown(rl.c.KEY_S)) input_dir = input_dir.sub(forward);
        if (rl.c.IsKeyDown(rl.c.KEY_D)) input_dir = input_dir.add(right);
        if (rl.c.IsKeyDown(rl.c.KEY_A)) input_dir = input_dir.sub(right);

        input_dir = input_dir.normalizeOrZero();
        const has_input = input_dir.lengthSquared() > 0.0;

        // 3. Gravidade e Mecânica de Salto (Eixo Y)
        if (controller.is_grounded) {
            if (rl.c.IsKeyPressed(rl.c.KEY_SPACE)) {
                controller.velocity.y = controller.jump_impulse;
                controller.is_grounded = false;
            }
        } else {
            // Aceleração da gravidade puxando para baixo
            controller.velocity.y -= controller.gravity * dt;
            if (controller.velocity.y < controller.terminal_velocity) {
                controller.velocity.y = controller.terminal_velocity;
            }

            // Salto com altura variável: soltar o Espaço durante a subida corta a velocidade vertical
            if (controller.velocity.y > 0.0 and rl.c.IsKeyReleased(rl.c.KEY_SPACE)) {
                controller.velocity.y *= controller.jump_cut_factor;
            }
        }

        // 4. Física Horizontal com Inércia (Plano XZ)
        var horiz_vel = Vec3.new(controller.velocity.x, 0.0, controller.velocity.z);
        const current_speed = horiz_vel.length();

        if (has_input) {
            // No ar, a aceleração é multiplicada pelo air_control_factor
            const accel = if (controller.is_grounded)
                controller.acceleration
            else
                controller.acceleration * controller.air_control_factor;

            if (current_speed > 0.5) {
                const vel_dir = horiz_vel.scale(1.0 / current_speed);
                const dot = vel_dir.dot(input_dir);

                // Derrapagem só ocorre quando em contato com o solo
                if (controller.is_grounded and dot < -0.4) {
                    const new_speed = @max(current_speed - controller.skid_deceleration * dt, 0.0);
                    if (new_speed == 0.0) {
                        horiz_vel = Vec3.ZERO;
                    } else {
                        horiz_vel = vel_dir.scale(new_speed);
                    }
                } else {
                    // Curva com inércia: preserva momentum enquanto alinha o vetor suavemente
                    const turn_speed = if (controller.is_grounded)
                        controller.turn_speed
                    else
                        controller.turn_speed * controller.air_control_factor;
                    const turn_factor = std.math.clamp(turn_speed * dt, 0.0, 1.0);
                    const steered_dir = vel_dir.lerp(input_dir, turn_factor).normalizeOrZero();
                    const new_speed = @min(current_speed + accel * dt, controller.max_speed);
                    horiz_vel = steered_dir.scale(new_speed);
                }
            } else {
                // Saindo do repouso
                const new_speed = @min(current_speed + accel * dt, controller.max_speed);
                horiz_vel = input_dir.scale(new_speed);
            }
        } else {
            // Desaceleração: no chão aplica o atrito normal; no ar há pouca resistência (arrasto suave)
            const decel = if (controller.is_grounded)
                controller.deceleration
            else
                controller.deceleration * 0.25;

            if (current_speed > 0.0) {
                const new_speed = @max(current_speed - decel * dt, 0.0);
                if (new_speed == 0.0) {
                    horiz_vel = Vec3.ZERO;
                } else {
                    horiz_vel = horiz_vel.scale(new_speed / current_speed);
                }
            }
        }

        // Recompõe o vetor de velocidade total
        controller.velocity = Vec3.new(horiz_vel.x, controller.velocity.y, horiz_vel.z);

        // 5. Integração da posição no mundo
        var pos = self.position.add(controller.velocity.scale(dt));

        // 6. Colisão com a malha do terreno (triângulos estáticos classificados pela normal)
        // 6a. Paredes: empurra o corpo para fora em duas alturas (joelho e peito)
        const offsets = [_]f32{ -0.3, 0.3 };
        for (offsets) |offset| {
            var probe = Vec3.new(pos.x, pos.y + offset, pos.z);
            const before = probe;
            const pushed = collision.pushOutOfWalls(&probe, PLAYER_RADIUS);
            pos.x += probe.x - before.x;
            pos.z += probe.z - before.z;

            // Remove a componente da velocidade horizontal que aponta contra a parede
            if (!pushed.eql(Vec3.ZERO)) {
                const n = pushed.normalize();
                const into_wall = controller.velocity.dot(n);
                if (into_wall < 0.0) {
                    controller.velocity = controller.velocity.sub(n.scale(into_wall));
                }
            }
        }

        // 6b. Teto: bate a cabeça e cancela a subida
        const head_y = pos.y + PLAYER_HALF_HEIGHT;
        if (controller.velocity.y > 0.0) {
            if (collision.findCeiling(pos.x, pos.z, self.position.y)) |ceiling_y| {
                if (head_y >= ceiling_y) {
                    pos.y = ceiling_y - PLAYER_HALF_HEIGHT;
                    controller.velocity.y = 0.0;
                }
            }
        }

        // 6c. Piso: raio vertical para baixo a partir de um pouco acima dos pés
        const feet_y = pos.y - PLAYER_HALF_HEIGHT;
        const floor = collision.findFloor(pos.x, pos.z, feet_y + STEP_HEIGHT);

        var ground_normal = Vec3.Y;

        if (floor) |hit| {
            const snap_distance = STEP_HEIGHT + horiz_vel.length() * dt * 2.0;
            const falling = controller.velocity.y <= 0.0;

            if (falling and feet_y <= hit.y) {
                // Pousou (ou subiu um degrau): apoia os pés exatamente sobre o piso
                pos.y = hit.y + PLAYER_HALF_HEIGHT;
                controller.velocity.y = 0.0;
                controller.is_grounded = true;
                ground_normal = hit.normal;
            } else if (controller.is_grounded and falling and (feet_y - hit.y) <= snap_distance) {
                // Descendo rampa: gruda no piso em vez de ficar "voando"
                pos.y = hit.y + PLAYER_HALF_HEIGHT;
                controller.velocity.y = 0.0;
                ground_normal = hit.normal;
            } else {
                controller.is_grounded = false;
            }
        } else {
            controller.is_grounded = false;
        }

        // 6d. Queda no vazio: reaparece no ponto inicial
        if (pos.y < VOID_Y) {
            pos = SPAWN_POSITION;
            controller.velocity = Vec3.ZERO;
            controller.is_grounded = false;
        }

        self.position = pos;

        // 7. Rotação visual: direção (yaw) + inclinação sutil do corpo conforme o terreno
        // 7a. Yaw suave voltado para a direção horizontal do movimento (menor caminho angular)
        if (horiz_vel.lengthSquared() > 0.05) {
            const move_dir = horiz_vel.normalize();
            const target_yaw = std.math.atan2(-move_dir.x, -move_dir.z);
            const diff = @mod(target_yaw - controller.facing_yaw + std.math.pi, std.math.tau) - std.math.pi;
            const rotation_speed: f32 = 10.0;
            const t = std.math.clamp(rotation_speed * dt, 0.0, 1.0);
            controller.facing_yaw += diff * t;
        }

        // 7b. Inclinação estilo SM64: só a parte da inclinação do terreno na direção em que
        // o personagem olha (subida/descida). Em ladeira transversal a inclinação é zero.
        const facing = Vec3.new(-@sin(controller.facing_yaw), 0.0, -@cos(controller.facing_yaw));
        var target_tilt = Quat.IDENTITY;
        if (controller.is_grounded) {
            const right_vec = facing.cross(Vec3.Y);
            // Normal do piso sem a componente lateral: fica só o "pitch" ao longo do olhar
            const along = ground_normal.sub(right_vec.scale(ground_normal.dot(right_vec))).normalizeOrZero();
            if (!along.eql(Vec3.ZERO) and along.y > 0.0) {
                const slope_angle = std.math.atan2(along.dot(facing), along.y);
                const tilt_angle = std.math.clamp(
                    slope_angle * controller.tilt_strength,
                    -controller.max_tilt_angle,
                    controller.max_tilt_angle,
                );
                target_tilt = Quat.fromAxisAngle(Vec3.Y.cross(facing).normalizeOrZero(), tilt_angle);
            }
        }
        const tilt_t = std.math.clamp(controller.tilt_smoothing * dt, 0.0, 1.0);
        controller.tilt = controller.tilt.slerp(target_tilt, tilt_t);

        // Rotação final = inclinação * yaw * compensação do cone (ponta aponta para -Z)
        self.rotation = controller.tilt
            .mul(Quat.fromRotationY(controller.facing_yaw))
            .mul(Quat.fromRotationX(-std.math.pi * 0.5));
    }

    // 💥 Reage a eventos de dano, coleta de itens e piscar de invulnerabilidade
    pub fn updateInteractionsAndStatus(self: *Player, dt: f32, interactions: *InteractionWorld) void {
        // 1. Dano sofrido por inimigos ou perigos
        for (interactions.damage_events.items) |ev| {
            if (self.stats.invulnerability_timer <= 0.0) {
                self.stats.health -|= ev.damage;
                self.stats.invulnerability_timer = 1.2; // 1.2s de invulnerabilidade

                var knockback_dir = self.position.sub(ev.source_pos);
                knockback_dir.y = 0.0;
                knockback_dir = knockback_dir.normalizeOrZero();

                self.controller.velocity = knockback_dir.scale(ev.knockback).add(Vec3.Y.scale(5.0));
                self.controller.is_grounded = false;

                std.log.info(
                    "💥 Jogador atingido! Dano: {d}, Vida restante: {d}",
                    .{ ev.damage, self.stats.health },
                );
            }
        }

        // 2. Coleta de itens no mapa
        for (interactions.collect_events.items) |ev| {
            switch (ev.kind) {
                .Coin => {
                    self.stats.coins += ev.value;
                    std.log.info("🪙 Moeda coletada! Total: {d}", .{self.stats.coins});
                },
                .Heart => {
                    self.stats.health = @min(self.stats.health + ev.value, self.stats.max_health);
                    std.log.info("❤️ Vida restaurada! Vida atual: {d}", .{self.stats.health});
                },
                .Star => {
                    std.log.info("⭐ Estrela coletada!", .{});
                },
                .Special => |name| {
                    std.log.info("🎁 Item especial obtido: {s}!", .{name});
                },
            }
        }

        // 3. Efeito de piscar durante o período de invulnerabilidade
        if (self.stats.invulnerability_timer > 0.0) {
            self.stats.invulnerability_timer -= dt;
            const blink_phase: u32 = @intFromFloat(@max(0.0, self.stats.invulnerability_timer * 10.0));
            self.visible = (blink_phase % 2) != 0;
        } else {
            self.visible = true;
        }
    }

    pub fn draw(self: *Player) void {
        if (!self.visible) return;

        // Centraliza o cone do Raylib (base em -0.6, ponta em +0.6) antes de aplicar a rotação Quaternion
        const center_offset = rl.c.MatrixTranslate(0.0, -PLAYER_HALF_HEIGHT, 0.0);
        const rot_mat = rl.quatToMatrix(self.rotation);
        self.model.transform = rl.c.MatrixMultiply(center_offset, rot_mat);

        rl.c.DrawModel(self.model, rl.toRlVec3(self.position), 1.0, rl.c.WHITE);
    }
};
