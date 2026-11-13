const std = @import("std");
const rl = @import("../../rl.zig");
const math = @import("../../math.zig");
const Vec3 = math.Vec3;
const collision_mod = @import("collision.zig");
const LevelCollision = collision_mod.LevelCollision;
const display = @import("../../settings/display.zig");

pub const DEFAULT_LEVEL_PATH: [:0]const u8 = "assets/levels/Scene.glb";
pub const FALLBACK_LEVEL_PATH: [:0]const u8 = "../assets/levels/Scene.glb";

// 📦 Gerenciador de fases e ciclo de vida dos terrenos (equivalente ao TerrainPlugin)
pub const TerrainManager = struct {
    current_path: [:0]const u8 = DEFAULT_LEVEL_PATH,
    model: ?rl.c.Model = null,

    pub fn init() TerrainManager {
        return .{};
    }

    pub fn deinit(self: *TerrainManager) void {
        if (self.model) |m| {
            rl.c.UnloadModel(m);
            self.model = null;
        }
    }

    fn resolveAssetPath(path: [:0]const u8) [:0]const u8 {
        if (rl.c.FileExists(path.ptr)) {
            return path;
        }
        if (std.mem.eql(u8, path, DEFAULT_LEVEL_PATH) and rl.c.FileExists(FALLBACK_LEVEL_PATH.ptr)) {
            return FALLBACK_LEVEL_PATH;
        }
        return path;
    }

    fn transformPoint(mat: rl.c.Matrix, v: Vec3) Vec3 {
        const res = rl.c.Vector3Transform(.{ .x = v.x, .y = v.y, .z = v.z }, mat);
        return .{ .x = res.x, .y = res.y, .z = res.z };
    }

    fn readVertex(vertices: [*]const f32, idx: usize, mat: rl.c.Matrix) Vec3 {
        const base = idx * 3;
        const local = Vec3.new(vertices[base], vertices[base + 1], vertices[base + 2]);
        return transformPoint(mat, local);
    }

    /// Carrega (ou troca) o nível atual, configura shaders/texturas e reconstrói a malha de colisão
    pub fn loadLevel(
        self: *TerrainManager,
        path: [:0]const u8,
        disp: *const display.DisplaySystem,
        collision: *LevelCollision,
    ) !void {
        // Descarrega nível anterior se existir
        if (self.model) |old| {
            rl.c.UnloadModel(old);
            self.model = null;
        }
        collision.clear();

        const resolved_path = resolveAssetPath(path);
        self.current_path = resolved_path;

        std.log.info("Carregando terreno: {s}", .{resolved_path});
        const loaded_model = rl.c.LoadModel(resolved_path.ptr);

        // Configura materiais (shader difuso sem Phong e filtragem de textura com Repeat/Tiling)
        const mat_count: usize = @intCast(@max(0, loaded_model.materialCount));
        for (0..mat_count) |i| {
            if (display.REMOVE_SPECULAR_PHONG) {
                loaded_model.materials[i].shader = disp.lighting_shader;
            }
            var tex: rl.c.Texture2D = loaded_model.materials[i].maps[rl.c.MATERIAL_MAP_DIFFUSE].texture;
            if (tex.id != 0 and tex.id != rl.c.rlGetTextureIdDefault()) {
                display.configureModelTexture(&tex, disp.filtering_mode);
                loaded_model.materials[i].maps[rl.c.MATERIAL_MAP_DIFFUSE].texture = tex;
            }
        }

        // Extrai todos os triângulos das malhas do terreno para o sistema de colisão espacial XZ
        const mesh_count: usize = @intCast(@max(0, loaded_model.meshCount));
        for (0..mesh_count) |m_idx| {
            const mesh = loaded_model.meshes[m_idx];
            if (mesh.vertices == null) continue;
            const verts: [*]const f32 = mesh.vertices;
            const tri_count: usize = @intCast(@max(0, mesh.triangleCount));

            if (mesh.indices != null) {
                const indices: [*]const c_ushort = mesh.indices;
                for (0..tri_count) |t| {
                    const idx0: usize = @intCast(indices[t * 3 + 0]);
                    const idx1: usize = @intCast(indices[t * 3 + 1]);
                    const idx2: usize = @intCast(indices[t * 3 + 2]);
                    const a = readVertex(verts, idx0, loaded_model.transform);
                    const b = readVertex(verts, idx1, loaded_model.transform);
                    const c = readVertex(verts, idx2, loaded_model.transform);
                    try collision.addTriangle(a, b, c);
                }
            } else {
                for (0..tri_count) |t| {
                    const idx0 = t * 3 + 0;
                    const idx1 = t * 3 + 1;
                    const idx2 = t * 3 + 2;
                    const a = readVertex(verts, idx0, loaded_model.transform);
                    const b = readVertex(verts, idx1, loaded_model.transform);
                    const c = readVertex(verts, idx2, loaded_model.transform);
                    try collision.addTriangle(a, b, c);
                }
            }
        }

        try collision.rebuildIndices();
        self.model = loaded_model;
    }

    /// Troca de fase em tempo de execução (equivalente ao ChangeLevelEvent)
    pub fn changeLevel(
        self: *TerrainManager,
        new_path: [:0]const u8,
        disp: *const display.DisplaySystem,
        collision: *LevelCollision,
    ) !void {
        std.log.info("Trocando de terreno para: {s}", .{new_path});
        try self.loadLevel(new_path, disp, collision);
    }

    /// Reconfigura a filtragem de textura de todos os materiais do terreno em tempo real
    pub fn updateTextureFiltering(self: *TerrainManager, mode: display.TextureFilteringMode, fallback: display.CrispFallbackFilter) void {
        if (self.model) |m| {
            const mat_count: usize = @intCast(@max(0, m.materialCount));
            for (0..mat_count) |i| {
                var tex: rl.c.Texture2D = m.materials[i].maps[rl.c.MATERIAL_MAP_DIFFUSE].texture;
                if (tex.id != 0 and tex.id != rl.c.rlGetTextureIdDefault()) {
                    display.configureModelTextureWithFallback(&tex, mode, fallback);
                    m.materials[i].maps[rl.c.MATERIAL_MAP_DIFFUSE].texture = tex;
                }
            }
        }
    }

    /// Renderiza o modelo do terreno (com suporte a doubleSided conforme o material glTF)
    pub fn draw(self: *const TerrainManager) void {
        if (self.model) |m| {
            rl.c.rlDisableBackfaceCulling();
            rl.c.DrawModel(m, .{ .x = 0.0, .y = 0.0, .z = 0.0 }, 1.0, rl.c.WHITE);
            rl.c.rlEnableBackfaceCulling();
        }
    }
};
