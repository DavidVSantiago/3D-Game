const std = @import("std");
const math = @import("../../math.zig");
const Vec3 = math.Vec3;

// 📦 Tipo de item coletável
pub const CollectibleKind = union(enum) {
    Coin,
    Star,
    Heart,
    Special: []const u8,
};

// 🎯 Componente de Hitbox para objetos interativos
pub const Hitbox = struct {
    radius: f32,
    height: f32,

    pub fn sphere(radius: f32) Hitbox {
        return .{ .radius = radius, .height = radius * 2.0 };
    }

    pub fn cylinder(radius: f32, height: f32) Hitbox {
        return .{ .radius = radius, .height = height };
    }
};

// 💥 Resposta da colisão com o objeto
pub const Interactable = union(enum) {
    /// Inimigo / Espinho: causa dano ao jogador e knockback
    Hazard: struct {
        damage: u32,
        knockback: f32,
    },
    /// Moeda, Estrela, Chave, Item especial: coletado e desaparece
    Collectible: struct {
        kind: CollectibleKind,
        value: u32,
    },
    /// Obstáculo sólido dinâmico: empurra o jogador para fora (ex: caixas, pilares, barris)
    SolidObstacle,
    /// Zona de ativação de evento: checkpoints, portais, áreas secretas
    TriggerZone: struct {
        id: []const u8,
    },
};

// 📢 Eventos disparados pelas colisões
pub const PlayerDamageEvent = struct {
    damage: u32,
    source_pos: Vec3,
    knockback: f32,
};

pub const ItemCollectedEvent = struct {
    kind: CollectibleKind,
    value: u32,
};

pub const TriggerZoneEvent = struct {
    id: []const u8,
};

pub const InteractableObject = struct {
    position: Vec3,
    hitbox: Hitbox,
    interactable: Interactable,
    active: bool = true,
};

pub const InteractionWorld = struct {
    allocator: std.mem.Allocator,
    objects: std.ArrayListUnmanaged(InteractableObject) = .empty,
    damage_events: std.ArrayListUnmanaged(PlayerDamageEvent) = .empty,
    collect_events: std.ArrayListUnmanaged(ItemCollectedEvent) = .empty,
    trigger_events: std.ArrayListUnmanaged(TriggerZoneEvent) = .empty,

    pub fn init(allocator: std.mem.Allocator) InteractionWorld {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *InteractionWorld) void {
        self.objects.deinit(self.allocator);
        self.damage_events.deinit(self.allocator);
        self.collect_events.deinit(self.allocator);
        self.trigger_events.deinit(self.allocator);
    }

    pub fn clearEvents(self: *InteractionWorld) void {
        self.damage_events.clearRetainingCapacity();
        self.collect_events.clearRetainingCapacity();
        self.trigger_events.clearRetainingCapacity();
    }

    pub fn spawnObject(self: *InteractionWorld, obj: InteractableObject) !void {
        try self.objects.append(self.allocator, obj);
    }

    // 🎮 Sistema que detecta a sobreposição entre o jogador e objetos interativos no mundo
    pub fn update(self: *InteractionWorld, player_pos: *Vec3) void {
        const player_radius: f32 = 0.5;
        const player_feet = player_pos.y - 0.6;
        const player_head = player_pos.y + 0.6;

        for (self.objects.items) |*obj| {
            if (!obj.active) continue;

            const obj_pos = obj.position;
            const obj_feet = obj_pos.y - obj.hitbox.height * 0.5;
            const obj_head = obj_pos.y + obj.hitbox.height * 0.5;

            // Teste de sobreposição no eixo vertical Y
            const vertical_overlap = player_head >= obj_feet and player_feet <= obj_head;
            if (!vertical_overlap) continue;

            // Teste de distância no plano horizontal XZ
            const dx = player_pos.x - obj_pos.x;
            const dz = player_pos.z - obj_pos.z;
            const dist_sq = dx * dx + dz * dz;
            const min_dist = player_radius + obj.hitbox.radius;

            if (dist_sq < min_dist * min_dist) {
                const dist = @max(@sqrt(dist_sq), 1e-4);

                switch (obj.interactable) {
                    .Hazard => |h| {
                        self.damage_events.append(self.allocator, .{
                            .damage = h.damage,
                            .source_pos = obj_pos,
                            .knockback = h.knockback,
                        }) catch {};
                    },
                    .Collectible => |c| {
                        self.collect_events.append(self.allocator, .{
                            .kind = c.kind,
                            .value = c.value,
                        }) catch {};
                        // O item coletado é removido do mundo
                        obj.active = false;
                    },
                    .SolidObstacle => {
                        // Empurra o jogador para fora do obstáculo dinâmico
                        const push_dir = Vec3.new(dx / dist, 0.0, dz / dist);
                        const overlap = min_dist - dist;
                        player_pos.* = player_pos.add(push_dir.scale(overlap));
                    },
                    .TriggerZone => |tz| {
                        self.trigger_events.append(self.allocator, .{
                            .id = tz.id,
                        }) catch {};
                    },
                }
            }
        }
    }
};
