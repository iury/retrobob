const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig");

const Core = @import("cores/core.zig");
const Famibob = @import("cores/famibob/famibob.zig").Famibob;
const Gamebob = @import("cores/gamebob/gamebob.zig").Gamebob;

pub const ActiveCore = enum(u8) { unknown = 0, famibob = 1, gamebob = 2 };
const Ratio = enum(u8) { native = 1, ntsc = 2, pal = 3, standard = 4, widescreen = 5 };

const Action = enum(i32) {
    load_core = 1,
    load_game = 2,
    resume_game = 3,
    pause_game = 4,
    reset_game = 5,
    change_region = 8,
    unload_core = 9,
    change_slot = 11,
    save_state = 12,
    load_state = 13,
    persist_battery = 14,
    fullscreen = 21,
    change_ratio = 22,
    change_zoom = 23,
};

var core: ?Core = null;
var active_core: ActiveCore = .unknown;
var slot: u8 = 1;

var audio_stream: ?c.AudioStream = null;
var audio_buffer: [3840]f32 = [_]f32{0} ** 3840;

var ratio: Ratio = .native;
var zoom: f32 = 3;
var fullscreen: bool = false;

fn loadROM(data: []const u8) bool {
    unloadCore();

    switch (active_core) {
        .famibob => {
            var famibob = Famibob.init(std.heap.c_allocator, data) catch |err| {
                switch (err) {
                    error.UnsupportedFile => {
                        std.debug.print("notify: Unsupported file\n", .{});
                    },
                    error.UnsupportedMapper => {
                        std.debug.print("notify: Unsupported mapper\n", .{});
                    },
                    error.UnsupportedSystem => {
                        std.debug.print("notify: Unsupported system\n", .{});
                    },
                    else => {},
                }
                return false;
            };

            core = famibob.core();
            resizeScreen();

            audio_stream = c.LoadAudioStream(48000, 32, 2);
            c.PlayAudioStream(audio_stream.?);

            c.notifyEvent(.region_support, 1);
            performAction(.change_region, @intFromEnum(famibob.cartridge.region), 0);
            c.notifyEvent(.has_battery, if (famibob.cartridge.battery) 1 else 0);

            if (famibob.cartridge.battery) {
                const _slot = slot;
                slot = 0;
                performAction(.load_state, 0, null);
                slot = _slot;
                performAction(.reset_game, 0, null);
            }
            return true;
        },
        .gamebob => {
            var gamebob = Gamebob.init(std.heap.c_allocator, data) catch |err| {
                switch (err) {
                    error.UnsupportedMapper => {
                        std.debug.print("notify: Unsupported mapper\n", .{});
                    },
                    else => {},
                }
                return false;
            };

            core = gamebob.core();
            resizeScreen();

            c.SetAudioStreamBufferSizeDefault(800);
            audio_stream = c.LoadAudioStream(48000, 32, 2);
            c.PlayAudioStream(audio_stream.?);

            setFPS(60);
            c.notifyEvent(.region_support, 0);
            performAction(.change_ratio, @intFromEnum(Ratio.native), 0);
            c.notifyEvent(.has_battery, if (gamebob.cartridge.battery) 1 else 0);

            if (gamebob.cartridge.battery) {
                const _slot = slot;
                slot = 0;
                performAction(.load_state, 0, null);
                slot = _slot;
                performAction(.reset_game, 0, null);
            }
            return true;
        },
        else => return false,
    }
}

fn unloadCore() void {
    if (audio_stream) |stream| {
        c.UnloadAudioStream(stream);
        audio_stream = null;
    }

    if (core) |*cr| {
        cr.deinit();
        core = null;
    }
}

export fn performAction(action: Action, param: u32, ptr: [*c]const u8) void {
    std.debug.print("Performing action {s} with value {d}...\n", .{ std.enums.tagName(Action, action).?, param });

    switch (action) {
        .load_core => {
            unloadCore();
            active_core = @enumFromInt(param);
            c.notifyEvent(.core_loaded, param);
        },
        .unload_core => {
            unloadCore();
            active_core = ActiveCore.unknown;
            c.notifyEvent(.core_unloaded, 0);
        },
        .load_game => {
            if (loadROM(ptr[0..param])) {
                c.notifyEvent(.game_loaded, 0);
                performAction(.resume_game, 0, null);
            } else {
                c.notifyEvent(.load_failed, 0);
                performAction(.unload_core, 0, null);
            }
        },
        .reset_game => {
            if (core) |*cr| {
                if (cr.state != .idle) {
                    cr.resetGame();
                    if (audio_stream) |stream| c.ResumeAudioStream(stream);
                    c.notifyEvent(.game_reset, 0);
                    performAction(.resume_game, 0, null);
                }
            }
        },
        .pause_game => {
            if (core) |*cr| {
                if (cr.state == .playing) {
                    cr.pauseGame();
                    if (audio_stream) |stream| c.PauseAudioStream(stream);
                    c.notifyEvent(.game_paused, 0);
                }
            }
        },
        .resume_game => {
            if (core) |*cr| {
                if (cr.state == .paused) {
                    cr.resumeGame();
                    if (audio_stream) |stream| c.ResumeAudioStream(stream);
                    c.notifyEvent(.game_resumed, 0);
                }
            }
        },
        .change_slot => {
            slot = @truncate(param);
            c.notifyEvent(.slot_changed, slot);
        },
        .save_state => {
            if (core) |*cr| {
                if (cr.state != .idle) {
                    cr.saveState(slot) catch {
                        std.debug.print("notify: Failed to save\n", .{});
                        return;
                    };
                    c.notifyEvent(.state_saved, slot);
                }
            }
        },
        .load_state => {
            if (core) |*cr| {
                if (cr.state != .idle) {
                    const loaded = cr.loadState(slot) catch {
                        std.debug.print("notify: Failed to load\n", .{});
                        return;
                    };

                    if (loaded) {
                        if (audio_stream) |stream| c.ResumeAudioStream(stream);
                        c.notifyEvent(.state_loaded, slot);
                        performAction(.resume_game, 0, null);
                    } else if (slot > 0) {
                        std.debug.print("notify: No state found at the slot {d}\n", .{slot});
                    }
                }
            }
        },
        .persist_battery => {
            if (core) |*cr| {
                if (cr.state != .idle) {
                    cr.persistBattery();
                    c.notifyEvent(.battery_persisted, 0);
                }
            }
        },
        .change_region => {
            if (core) |*cr| {
                const region = @as(Core.Region, @enumFromInt(param));
                if (cr.state != .idle) {
                    cr.changeRegion(region);
                    c.UnloadAudioStream(audio_stream.?);

                    if (region == .ntsc) {
                        setFPS(60);
                        c.SetAudioStreamBufferSizeDefault(800);
                        performAction(.change_ratio, @intFromEnum(Ratio.ntsc), 0);
                    } else {
                        setFPS(50);
                        c.SetAudioStreamBufferSizeDefault(960);
                        performAction(.change_ratio, @intFromEnum(Ratio.pal), 0);
                    }

                    audio_stream = c.LoadAudioStream(48000, 32, 2);
                    c.PlayAudioStream(audio_stream.?);
                }
                c.notifyEvent(.region_changed, param);
            }
        },
        .change_ratio => {
            ratio = @enumFromInt(param);
            resizeScreen();
            c.notifyEvent(.ratio_changed, param);
        },
        .change_zoom => {
            zoom = @floatFromInt(param);
            resizeScreen();
            c.notifyEvent(.zoom_changed, param);
        },
        .fullscreen => {
            if ((param == 0 and fullscreen) or param == 2) {
                if (param == 0) c.ToggleBorderlessWindowed();
                c.ShowCursor();
                fullscreen = false;
                resizeScreen();

                if (builtin.os.tag != .emscripten) {
                    const pos = c.GetMonitorPosition(c.GetCurrentMonitor());
                    const pos_x: i32 = @intFromFloat(pos.x);
                    const pos_y: i32 = @intFromFloat(pos.y);
                    const monitor_w: i32 = @intCast(c.GetMonitorWidth(c.GetCurrentMonitor()));
                    const monitor_h: i32 = @intCast(c.GetMonitorHeight(c.GetCurrentMonitor()));
                    const sw: i32 = @intCast(c.GetScreenWidth());
                    const sh: i32 = @intCast(c.GetScreenHeight());
                    c.SetWindowPosition(pos_x + @divTrunc((monitor_w - sw), 2), pos_y + @divTrunc((monitor_h - sh), 2));
                }
            } else if ((param == 0 and !fullscreen) or param == 1) {
                if (builtin.os.tag != .emscripten) {
                    const pos = c.GetMonitorPosition(c.GetCurrentMonitor());
                    c.SetWindowPosition(@intFromFloat(pos.x), @intFromFloat(pos.y));
                }

                fullscreen = true;
                resizeScreen();
                c.HideCursor();
                if (param == 0) c.ToggleBorderlessWindowed();
            }
        },
    }
}

fn handleFileDropped() void {
    const alloc = std.heap.c_allocator;
    const files = c.LoadDroppedFiles();
    defer c.UnloadDroppedFiles(files);

    const lower_path = std.ascii.allocLowerString(alloc, std.fs.path.basename(std.mem.span(files.paths[0]))) catch return;
    defer alloc.free(lower_path);

    if (std.mem.endsWith(u8, lower_path, ".nes")) {
        performAction(.load_core, @intFromEnum(ActiveCore.famibob), 0);

        const file = std.fs.openFileAbsoluteZ(files.paths[0], .{}) catch return;
        defer file.close();

        const buf = file.readToEndAlloc(alloc, @truncate(file.getEndPos() catch 0)) catch return;
        defer alloc.free(buf);

        performAction(.load_game, @truncate(buf.len), buf.ptr);

        if (std.mem.containsAtLeast(u8, lower_path, 1, "[pal]") or
            std.mem.containsAtLeast(u8, lower_path, 1, "(pal)") or
            std.mem.containsAtLeast(u8, lower_path, 1, "[e]") or
            std.mem.containsAtLeast(u8, lower_path, 1, "(e)") or
            std.mem.containsAtLeast(u8, lower_path, 1, "[europe]") or
            std.mem.containsAtLeast(u8, lower_path, 1, "(europe)"))
        {
            performAction(.change_region, @intFromEnum(Core.Region.pal), 0);
        }
    } else if (std.mem.endsWith(u8, lower_path, ".gb") or std.mem.endsWith(u8, lower_path, ".gbc")) {
        performAction(.load_core, @intFromEnum(ActiveCore.gamebob), 0);
        const file = std.fs.openFileAbsoluteZ(files.paths[0], .{}) catch return;
        defer file.close();
        const buf = file.readToEndAlloc(alloc, @truncate(file.getEndPos() catch 0)) catch return;
        defer alloc.free(buf);
        performAction(.load_game, @truncate(buf.len), buf.ptr);
    } else {
        performAction(.unload_core, 0, null);
        std.debug.print("notify: Unsupported file\n", .{});
    }
}

fn mainLoop() callconv(.C) void {
    if (c.IsFileDropped()) {
        handleFileDropped();
    }

    handleCmdKeys();

    if (core == null or core.?.state == .idle) {
        c.BeginDrawing();
        drawDragMsg();
        c.EndDrawing();
    } else {
        c.BeginDrawing();
        render();
        c.EndDrawing();
    }
}

fn handleCmdKeys() void {
    if (c.IsKeyPressed(c.KEY_ESCAPE)) {
        if (fullscreen) {
            performAction(.fullscreen, 0, 0);
        } else if (builtin.os.tag != .emscripten) {
            std.os.exit(0);
        }
    }

    if (c.IsKeyPressed(c.KEY_SPACE)) {
        if (core) |cr| {
            if (cr.state == .playing) {
                performAction(.pause_game, 0, 0);
            } else {
                performAction(.resume_game, 0, 0);
            }
        }
    } else if (c.IsKeyPressed(c.KEY_F3)) {
        if (core) |_| performAction(.reset_game, 0, 0);
    } else if (c.IsKeyPressed(c.KEY_F11)) {
        performAction(.fullscreen, 0, 0);
    } else if (c.IsKeyPressed(c.KEY_F1)) {
        if (core) |_| performAction(.save_state, 0, 0);
    } else if (c.IsKeyPressed(c.KEY_F4)) {
        if (core) |_| performAction(.load_state, 0, 0);
    }
}

fn render() void {
    if (core) |*cr| {
        const texture = cr.getTexture();

        if (cr.state == .playing) {
            c.SetWindowTitle(c.TextFormat("retrobob - %d fps", c.GetFPS()));
            c.ClearBackground(c.BLACK);
            cr.render();
        } else {
            c.SetWindowTitle(c.TextFormat("retrobob"));
        }

        updateAudioStream();
        c.notifyEvent(.end_frame, 0);

        const overscan: f32 = if (ratio == .ntsc) 8 else 0;

        const applied_zoom: f32 = @as(f32, @floatFromInt(c.GetScreenHeight())) / @as(f32, @floatFromInt(texture.height));
        const width: f32 = @floatFromInt(texture.width);
        const height: f32 = @floatFromInt(texture.height);
        var target_width: f32 = @floatFromInt(c.GetScreenWidth());
        const screen_width: f32 = target_width;

        if (fullscreen) {
            switch (ratio) {
                .native => target_width = width * applied_zoom,
                .ntsc => target_width = width * 8 / 7 * applied_zoom,
                .pal => target_width = width * 11 / 8 * applied_zoom,
                .standard => target_width = height * 4 / 3 * applied_zoom,
                .widescreen => target_width = height * 16 / 9 * applied_zoom,
            }
        }

        c.DrawTexturePro(
            texture,
            .{ .x = 0, .y = overscan, .width = @floatFromInt(texture.width), .height = @as(f32, @floatFromInt(texture.height)) - overscan * 2 },
            .{ .x = (screen_width - target_width) / 2, .y = 0, .width = target_width, .height = @floatFromInt(c.GetScreenHeight()) },
            .{ .x = 0, .y = 0 },
            0.0,
            c.WHITE,
        );
    }
}

fn drawDragMsg() void {
    c.ClearBackground(c.RAYWHITE);
    const fontSize = 20;
    const msg = "Drag a ROM file to start";
    c.DrawText(msg, @divTrunc((c.GetScreenWidth() - c.MeasureText(msg, fontSize)), 2), @divTrunc((c.GetScreenHeight() - fontSize), 2), fontSize, c.LIGHTGRAY);
}

fn resizeScreen() void {
    const width = if (core) |cr| cr.game_width else 256;
    const height = if (core) |cr| cr.game_height else 240;
    var applied_zoom = zoom;

    if (fullscreen) {
        const h: f32 = @floatFromInt(c.GetMonitorHeight(c.GetCurrentMonitor()));
        applied_zoom = h / height;
    }

    switch (ratio) {
        .native => {
            c.SetWindowSize(@intFromFloat(width * applied_zoom), @intFromFloat(height * applied_zoom));
        },
        .ntsc => {
            c.SetWindowSize(@intFromFloat(@trunc(width * 8 / 7) * applied_zoom), @intFromFloat((height - 16) * applied_zoom));
        },
        .pal => {
            c.SetWindowSize(@intFromFloat(@trunc(width * 11 / 8) * applied_zoom), @intFromFloat(height * applied_zoom));
        },
        .standard => {
            c.SetWindowSize(@intFromFloat(@trunc(height * 4 / 3) * applied_zoom), @intFromFloat(height * applied_zoom));
        },
        .widescreen => {
            c.SetWindowSize(@intFromFloat(@trunc(height * 16 / 9) * applied_zoom), @intFromFloat(height * applied_zoom));
        },
    }
}

fn setFPS(fps: c_int) void {
    c.SetTargetFPS(fps);
}

fn updateAudioStream() void {
    if (core) |*cr| {
        if (audio_stream) |s| {
            if (c.IsAudioStreamPlaying(s)) {
                const sample_size: usize = if (cr.region == .ntsc) 800 else 960;
                if (builtin.os.tag == .emscripten) {
                    _ = cr.fillAudioBuffer(audio_buffer[0 .. sample_size * 4]);
                } else {
                    const samples = cr.fillAudioBuffer(audio_buffer[0 .. sample_size * 4]);
                    if (c.IsAudioStreamProcessed(s)) {
                        c.UpdateAudioStream(s, &audio_buffer, @intCast(samples));
                    }
                }
            } else {
                @memset(&audio_buffer, 0);
            }
        }
    }
}

pub fn main() void {
    c.InitWindow(768, 720, "retrobob");
    c.InitAudioDevice();
    c.SetExitKey(0);
    setFPS(60);

    if (builtin.os.tag == .emscripten) {
        std.os.emscripten.emscripten_cancel_main_loop();
        std.os.emscripten.emscripten_set_main_loop(mainLoop, 0, 1);
    } else {
        while (!c.WindowShouldClose()) {
            mainLoop();
        }

        unloadCore();
        c.CloseAudioDevice();
        c.CloseWindow();
    }
}

export fn getAudioBuffer() usize {
    return @intFromPtr(&audio_buffer);
}

export fn terminate() void {
    unloadCore();
    if (builtin.os.tag == .emscripten) {
        std.os.emscripten.emscripten_cancel_main_loop();
        std.os.emscripten.emscripten_force_exit(0);
    }
}
