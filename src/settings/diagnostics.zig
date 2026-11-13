const std = @import("std");
const builtin = @import("builtin");
const rl = @import("../rl.zig");
const display = @import("display.zig");

const GL_VENDOR: c_uint = 0x1F00;
const GL_RENDERER: c_uint = 0x1F01;
const GL_VERSION: c_uint = 0x1F02;

extern fn glGetString(name: c_uint) callconv(.c) ?[*:0]const u8;
extern fn timeBeginPeriod(uPeriod: c_uint) callconv(.winapi) c_uint;
extern fn timeEndPeriod(uPeriod: c_uint) callconv(.winapi) c_uint;

/// 🛠️ Modos de seleção de GPU para testes A/B
pub const GpuSelectionMode = enum {
    HighPerformance,
    Integrated,
    SoftwareWARP,
    Auto,
};

/// 🛠️ Configuração consolidada de diagnósticos e renderização
pub const DiagnosticRenderConfig = struct {
    gpu_mode: GpuSelectionMode,
    vsync: bool,
    target_fps: ?f32,

    /// Lê a configuração a partir de variáveis de ambiente com fallback para display.zig
    pub fn loadConfiguration() DiagnosticRenderConfig {
        const env_gpu = rl.getEnv("GPU_MODE") orelse display.GPU_MODE_PREFERENCE;
        const gpu_mode: GpuSelectionMode = if (std.ascii.eqlIgnoreCase(env_gpu, "integrated") or
            std.ascii.eqlIgnoreCase(env_gpu, "low") or
            std.ascii.eqlIgnoreCase(env_gpu, "igpu") or
            std.ascii.eqlIgnoreCase(env_gpu, "intel"))
            .Integrated
        else if (std.ascii.eqlIgnoreCase(env_gpu, "software") or
            std.ascii.eqlIgnoreCase(env_gpu, "cpu") or
            std.ascii.eqlIgnoreCase(env_gpu, "warp"))
            .SoftwareWARP
        else if (std.ascii.eqlIgnoreCase(env_gpu, "high") or
            std.ascii.eqlIgnoreCase(env_gpu, "discrete") or
            std.ascii.eqlIgnoreCase(env_gpu, "dgpu") or
            std.ascii.eqlIgnoreCase(env_gpu, "nvidia") or
            std.ascii.eqlIgnoreCase(env_gpu, "rtx"))
            .HighPerformance
        else
            .Auto;

        const vsync: bool = if (rl.getEnv("VSYNC")) |v| blk: {
            if (std.ascii.eqlIgnoreCase(v, "off") or
                std.ascii.eqlIgnoreCase(v, "novsync") or
                std.ascii.eqlIgnoreCase(v, "immediate") or
                std.ascii.eqlIgnoreCase(v, "false") or
                std.ascii.eqlIgnoreCase(v, "0"))
            {
                break :blk false;
            }
            break :blk true;
        } else display.ENABLE_VSYNC;

        const target_fps: ?f32 = if (rl.getEnv("TARGET_FPS")) |val| blk: {
            if (std.ascii.eqlIgnoreCase(val, "none") or
                std.ascii.eqlIgnoreCase(val, "0") or
                std.ascii.eqlIgnoreCase(val, "unlimited") or
                std.ascii.eqlIgnoreCase(val, "off"))
            {
                break :blk null;
            }
            const parsed = std.fmt.parseFloat(f32, val) catch break :blk display.TARGET_FPS;
            break :blk if (parsed > 0.0) parsed else null;
        } else display.TARGET_FPS;

        return .{
            .gpu_mode = gpu_mode,
            .vsync = vsync,
            .target_fps = target_fps,
        };
    }

    /// Configura as flags de inicialização da janela do Raylib (VSync, MSAA, Redimensionamento)
    pub fn applyWindowFlags(self: DiagnosticRenderConfig) void {
        var flags: c_uint = 0;
        if (display.WINDOW_RESIZABLE) {
            flags |= rl.c.FLAG_WINDOW_RESIZABLE;
        }
        // Quando há um FPS Cap explícito (ex: 60 FPS num monitor de 120Hz), o limitador de alta precisão
        // controla o tempo exato de quadro; caso contrário usa o VSync nativo do monitor.
        if (self.vsync and self.target_fps == null) {
            flags |= rl.c.FLAG_VSYNC_HINT;
        }
        if (!display.DISABLE_MSAA) {
            flags |= rl.c.FLAG_MSAA_4X_HINT;
        }
        rl.c.SetConfigFlags(flags);
    }
};

/// ⏱️ Monitor de telemetria, hardware e limitador de taxa de quadros
pub const DiagnosticsSystem = struct {
    allocator: std.mem.Allocator,
    config: DiagnosticRenderConfig,
    frame_times_ms: std.ArrayListUnmanaged(f32) = .empty,
    sort_buffer: std.ArrayListUnmanaged(f32) = .empty,
    last_log_seconds: f64 = 0.0,
    last_frame_time: f64 = 0.0,
    current_dt: f32 = 1.0 / 60.0,
    warmup_frames: u32 = 2,
    stutters_count: u32 = 0,
    total_frames: u64 = 0,
    logged_hardware: bool = false,
    gpu_name: []const u8 = "GPU",
    current_fps: f32 = 60.0,
    current_avg_ms: f32 = 16.67,

    pub fn init(allocator: std.mem.Allocator, config: DiagnosticRenderConfig) DiagnosticsSystem {
        if (builtin.os.tag == .windows) {
            _ = timeBeginPeriod(1);
        }
        const now = rl.c.GetTime();
        return .{
            .allocator = allocator,
            .config = config,
            .last_log_seconds = now,
            .last_frame_time = now,
        };
    }

    pub fn deinit(self: *DiagnosticsSystem) void {
        if (builtin.os.tag == .windows) {
            _ = timeEndPeriod(1);
        }
        self.frame_times_ms.deinit(self.allocator);
        self.sort_buffer.deinit(self.allocator);
    }

    /// Reseta o relógio de quadro logo após o carregamento pesado de assets na inicialização
    pub fn resetTimerAfterLoading(self: *DiagnosticsSystem) void {
        const now = rl.c.GetTime();
        self.last_frame_time = now;
        self.last_log_seconds = now;
        self.warmup_frames = 2;
    }

    /// 🖥️ Loga com detalhes o dispositivo gráfico, backend e driver assim que o contexto OpenGL inicia
    pub fn logHardwareInfoOnce(self: *DiagnosticsSystem) void {
        if (self.logged_hardware) return;
        self.logged_hardware = true;

        const renderer_c = glGetString(GL_RENDERER);
        const vendor_c = glGetString(GL_VENDOR);
        const version_c = glGetString(GL_VERSION);

        const renderer = if (renderer_c) |p| std.mem.span(p) else "OpenGL Device";
        const vendor = if (vendor_c) |p| std.mem.span(p) else "Unknown Vendor";
        const version = if (version_c) |p| std.mem.span(p) else "OpenGL 3.3";

        self.gpu_name = renderer;

        var cap_buf: [64]u8 = undefined;
        const cap_info = if (self.config.target_fps) |fps|
            std.fmt.bufPrint(&cap_buf, "{d:.0} FPS cravados", .{fps}) catch "60 FPS cravados"
        else
            "Ilimitado / VSync nativo";

        std.log.info("============================================================", .{});
        std.log.info("🎮 [GPU DIAGNOSTICS] Adaptador Ativo (Raylib / OpenGL 3.3):", .{});
        std.log.info("   • Dispositivo:      {s}", .{renderer});
        std.log.info("   • Fornecedor:       {s}", .{vendor});
        std.log.info("   • Backend Gráfico:  OpenGL 3.3 Core ({s})", .{@tagName(builtin.os.tag)});
        std.log.info("   • Preferência GPU:  {s}", .{@tagName(self.config.gpu_mode)});
        std.log.info("   • Limite de FPS:    {s}", .{cap_info});
        std.log.info("   • Versão Driver:    {s}", .{version});
        std.log.info("============================================================", .{});
    }

    /// 🎯 Finaliza o quadro: aplica o limitador de FPS de alta precisão e registra as métricas de frame pacing
    pub fn endFrameAndMeasure(self: *DiagnosticsSystem) f32 {
        self.logHardwareInfoOnce();

        // 1. Limitador de taxa de quadros (WaitTime + Spin-Loop com precisão sub-milissegundo)
        if (self.config.target_fps) |fps| {
            if (fps > 0.0) {
                const target_duration: f64 = 1.0 / @as(f64, fps);
                const elapsed = rl.c.GetTime() - self.last_frame_time;
                if (elapsed < target_duration) {
                    const remaining = target_duration - elapsed;
                    if (remaining > 0.002) {
                        rl.c.WaitTime(remaining - 0.0018);
                    }
                    while (rl.c.GetTime() - self.last_frame_time < target_duration) {
                        std.atomic.spinLoopHint();
                    }
                }
            }
        }

        // 2. Medição exata da duração do quadro concluído
        const now = rl.c.GetTime();
        if (self.warmup_frames > 0) {
            self.warmup_frames -= 1;
            self.last_frame_time = now;
            self.last_log_seconds = now;
            return 1.0 / 60.0;
        }
        const dt: f32 = @floatCast(@max(0.0001, now - self.last_frame_time));
        self.last_frame_time = now;
        self.current_dt = dt;

        const dt_ms = dt * 1000.0;
        self.current_avg_ms = dt_ms;
        self.current_fps = if (dt > 0.0) 1.0 / dt else 0.0;
        self.frame_times_ms.append(self.allocator, dt_ms) catch {};
        self.total_frames += 1;

        const spike_threshold: f32 = if (self.config.target_fps) |target|
            if (target <= 60.0) (1000.0 / target) * 1.35 else 22.0
        else
            22.0;

        if (dt_ms > spike_threshold) {
            self.stutters_count += 1;
        }

        // 3. Relatório consolidado a cada 1 segundo no console e barra de título
        if (now - self.last_log_seconds >= 1.0 and self.frame_times_ms.items.len > 0) {
            const items = self.frame_times_ms.items;
            const count = items.len;
            const count_f: f32 = @floatFromInt(count);

            var sum: f32 = 0.0;
            for (items) |t| sum += t;
            const avg_ms = sum / count_f;
            const fps = if (avg_ms > 0.0) 1000.0 / avg_ms else 0.0;

            self.sort_buffer.clearRetainingCapacity();
            self.sort_buffer.appendSlice(self.allocator, items) catch {};
            const sorted = self.sort_buffer.items;
            std.mem.sort(f32, sorted, {}, std.sort.asc(f32));

            const min_ms = if (sorted.len > 0) sorted[0] else 0.0;
            const max_ms = if (sorted.len > 0) sorted[sorted.len - 1] else 0.0;

            const idx_99 = @min(@as(usize, @intFromFloat(@floor(count_f * 0.99))), sorted.len - 1);
            const p99_ms = sorted[idx_99];
            const low_1_percent_fps = if (p99_ms > 0.0) 1000.0 / p99_ms else 0.0;

            var var_sum: f32 = 0.0;
            for (items) |t| {
                const d = t - avg_ms;
                var_sum += d * d;
            }
            const variance = var_sum / count_f;
            const std_dev_ms = @sqrt(variance);

            var target_buf: [32]u8 = undefined;
            const target_str = if (self.config.target_fps) |t|
                std.fmt.bufPrint(&target_buf, " (Alvo: {d:.0})", .{t}) catch ""
            else
                "";

            var title_buf: [256]u8 = undefined;
            if (std.fmt.bufPrint(
                title_buf[0 .. title_buf.len - 1],
                "{s} | {s} | {d:.0} FPS{s} ({d:.1}ms) | 1% Low: {d:.0} FPS | Spikes: {d}",
                .{ display.WINDOW_TITLE, self.gpu_name, fps, target_str, avg_ms, low_1_percent_fps, self.stutters_count },
            )) |slice| {
                title_buf[slice.len] = 0;
                rl.c.SetWindowTitle(&title_buf[0]);
            } else |_| {
                rl.c.SetWindowTitle(display.WINDOW_TITLE.ptr);
            }

            std.log.info(
                "⏱️ [PERF] FPS: {d:5.1}{s} (Méd: {d:4.2}ms) | 1% Low: {d:5.1} FPS ({d:4.2}ms) | Min/Máx: {d:4.2}/{d:4.2}ms | Jitter(σ): {d:4.2}ms | Spikes: {d}",
                .{ fps, target_str, avg_ms, low_1_percent_fps, p99_ms, min_ms, max_ms, std_dev_ms, self.stutters_count },
            );

            self.frame_times_ms.clearRetainingCapacity();
            self.stutters_count = 0;
            self.last_log_seconds = now;
        }

        return dt;
    }

    /// Alterna o limitador de FPS entre 60.0 FPS cravados e Livre (null)
    pub fn toggleTargetFps(self: *DiagnosticsSystem) ?f32 {
        if (self.config.target_fps) |_| {
            self.config.target_fps = null;
        } else {
            self.config.target_fps = 60.0;
        }
        return self.config.target_fps;
    }
};
