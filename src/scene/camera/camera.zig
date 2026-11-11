const std = @import("std");
const rl = @import("../../rl.zig");
const math = @import("../../math.zig");
const Vec3 = math.Vec3;
const Quat = math.Quat;

// 🎥 Configuração e estado da Câmera estilo Lakitu (Super Mario 64)
pub const LakituCamera = struct {
    distance: f32 = 16.0, // Distância orbital do foco
    height: f32 = 4.0, // Altura relativa acima do foco
    focus_offset_y: f32 = 0.8, // Offset vertical do ponto mirado no jogador
    yaw: f32 = 0.0, // Ângulo horizontal orbital em radianos
    pitch: f32 = 0.22, // Ligeiramente inclinada para baixo para boa visão do nível
    follow_speed: f32 = 6.0, // Suavização do movimento de perseguição
    rotation_speed: f32 = 2.4, // Velocidade de giro manual por teclas
    mouse_sensitivity: f32 = 0.004, // Sensibilidade do mouse ao segurar botão direito
    current_focus: Vec3 = Vec3.ZERO, // Posição suavizada do foco atual
    position: Vec3 = Vec3.ZERO, // Posição atual da lente (eye) no mundo

    pub fn init() LakituCamera {
        var cam = LakituCamera{};
        const horizontal_dist = cam.distance * @cos(cam.pitch);
        cam.position = Vec3.new(
            horizontal_dist * @sin(cam.yaw),
            cam.height + cam.distance * @sin(cam.pitch),
            horizontal_dist * @cos(cam.yaw),
        );
        return cam;
    }

    pub fn forward(self: *const LakituCamera) Vec3 {
        return self.current_focus.sub(self.position).normalizeOrZero();
    }

    pub fn right(self: *const LakituCamera) Vec3 {
        return self.forward().cross(Vec3.Y).normalizeOrZero();
    }

    pub fn toRaylibCamera(self: *const LakituCamera) rl.c.Camera3D {
        return .{
            .position = rl.toRlVec3(self.position),
            .target = rl.toRlVec3(self.current_focus),
            .up = rl.toRlVec3(Vec3.Y),
            .fovy = 45.0, // Mesmo FOV vertical padrão do Bevy (FRAC_PI_4 = 45°)
            .projection = rl.c.CAMERA_PERSPECTIVE,
        };
    }

    // 🎮 Sistema de controle e perseguição suave estilo Lakitu
    pub fn update(self: *LakituCamera, dt: f32, player_pos: Vec3, player_rotation: Quat) void {
        if (dt <= 0.0) return;

        // 1. Rotação manual por teclas: Q/E ou Setas Esquerda/Direita
        if (rl.c.IsKeyDown(rl.c.KEY_Q) or rl.c.IsKeyDown(rl.c.KEY_LEFT)) {
            self.yaw += self.rotation_speed * dt;
        }
        if (rl.c.IsKeyDown(rl.c.KEY_E) or rl.c.IsKeyDown(rl.c.KEY_RIGHT)) {
            self.yaw -= self.rotation_speed * dt;
        }

        // 2. Botão R: Recentraliza a câmera instantaneamente atrás do personagem (como no SM64)
        if (rl.c.IsKeyPressed(rl.c.KEY_R)) {
            const facing = player_rotation.mulVec3(Vec3.Y);
            const target_yaw = std.math.atan2(-facing.x, -facing.z);
            self.yaw = target_yaw;
        }

        // 3. Controle por mouse: segurar botão direito e arrastar para girar
        if (rl.c.IsMouseButtonDown(rl.c.MOUSE_BUTTON_RIGHT)) {
            const delta = rl.c.GetMouseDelta();
            self.yaw -= delta.x * self.mouse_sensitivity;
            self.pitch = std.math.clamp(
                self.pitch + delta.y * self.mouse_sensitivity,
                -0.05,
                1.1, // Trava para não inverter nem entrar no chão
            );
        }

        // 4. Zoom na câmera com a roda do mouse (Scroll Wheel)
        const wheel = rl.c.GetMouseWheelMove();
        if (wheel != 0.0) {
            self.distance = std.math.clamp(self.distance - wheel * 1.2, 6.0, 30.0);
        }

        // 5. Suavização do ponto de foco (acompanha o jogador sem 'trancos')
        const target_focus = player_pos.add(Vec3.Y.scale(self.focus_offset_y));
        const focus_t = std.math.clamp(self.follow_speed * dt, 0.0, 1.0);
        self.current_focus = self.current_focus.lerp(target_focus, focus_t);

        // 6. Cálculo da posição orbital da câmera
        const horizontal_dist = self.distance * @cos(self.pitch);
        const offset = Vec3.new(
            horizontal_dist * @sin(self.yaw),
            self.height + self.distance * @sin(self.pitch),
            horizontal_dist * @cos(self.yaw),
        );
        const desired_pos = self.current_focus.add(offset);

        // 7. Interpolação suave da posição da câmera
        self.position = self.position.lerp(desired_pos, focus_t);
    }
};
