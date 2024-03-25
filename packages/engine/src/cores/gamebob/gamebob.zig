const std = @import("std");
const builtin = @import("builtin");
const c = @import("../../c.zig");

const Core = @import("../core.zig");
const CPU = @import("cpu.zig").CPU;
const PPU = @import("ppu.zig").PPU;
const APU = @import("apu.zig").APU;
const Clock = @import("clock.zig").Clock;
const Cartridge = @import("cartridge.zig").Cartridge;
const Input = @import("input.zig").Input;
const Timer = @import("timer.zig").Timer;
const Proxy = @import("../../proxy.zig").Proxy;
const Memory = @import("../../memory.zig").Memory;
const MemoryBus = @import("memory_bus.zig").MemoryBus;
const ROMOnly = @import("mappers/rom_only.zig").ROMOnly;
const MBC1 = @import("mappers/mbc1.zig").MBC1;
const MBC2 = @import("mappers/mbc2.zig").MBC2;
const MBC3 = @import("mappers/mbc3.zig").MBC3;
const MBC5 = @import("mappers/mbc5.zig").MBC5;
const RTC = @import("mappers/rtc.zig").RTC;

const PALETTES = @import("dmg_palettes.zig").PALETTES;
const FRAG = @embedFile("shader.glsl");

pub const Gamebob = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    cpu: CPU,
    ppu: *PPU,
    apu: *APU,
    input: *Input,
    timer: *Timer,
    bus: *MemoryBus,
    mapper: Memory(u16, u8),
    cartridge: *Cartridge,
    clock: Clock(Self),
    dmg_colors: u2 = 0,
    rtc: ?RTC,

    texture: c.RenderTexture2D = undefined,
    shader: c.Shader = undefined,
    render_width: f32 = 160,
    render_height: f32 = 144,

    fn initTexture(self: *Self) void {
        self.texture = c.LoadRenderTexture(@intFromFloat(self.render_width), @intFromFloat(self.render_height));
        self.shader = c.LoadShaderFromMemory(0, FRAG);
    }

    fn deinitTexture(self: *Self) void {
        c.UnloadRenderTexture(self.texture);
        c.UnloadShader(self.shader);
    }

    pub fn getTexture(ctx: *anyopaque) c.Texture {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return self.texture.texture;
    }

    pub fn getShader(ctx: *anyopaque, source: c.Rectangle, dest: c.Rectangle) ?c.Shader {
        _ = dest;
        _ = source;
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return if (self.dmg_colors == 0) self.shader else null;
    }

    pub fn init(allocator: std.mem.Allocator, rom_data: []const u8) !*Self {
        const cartridge = try Cartridge.init(allocator, rom_data);

        var mapper: Memory(u16, u8) = undefined;
        var rtc: ?RTC = null;
        switch (cartridge.mapper_id) {
            0x00, 0x08, 0x09 => {
                var rom_only = try ROMOnly.init(allocator, cartridge);
                mapper = rom_only.memory();
            },
            0x01, 0x02, 0x03 => {
                var mbc1 = try MBC1.init(allocator, cartridge);
                mapper = mbc1.memory();
            },
            0x05, 0x06 => {
                var mbc2 = try MBC2.init(allocator, cartridge);
                mapper = mbc2.memory();
            },
            0x0f, 0x10 => {
                var mbc3 = try MBC3.init(allocator, cartridge, true);
                mapper = mbc3.memory();
                rtc = mbc3.rtc();
            },
            0x11, 0x12, 0x13 => {
                var mbc3 = try MBC3.init(allocator, cartridge, false);
                mapper = mbc3.memory();
            },
            0x19, 0x1a, 0x1b => {
                var mbc5 = try MBC5.init(allocator, cartridge, false);
                mapper = mbc5.memory();
            },
            0x1c, 0x1d, 0x1e => {
                var mbc5 = try MBC5.init(allocator, cartridge, true);
                mapper = mbc5.memory();
            },
            else => {
                return error.UnsupportedMapper;
            },
        }

        var bus = try MemoryBus.init(allocator);
        bus.mapper = mapper;

        var ppu = try PPU.init(allocator, bus.memory());
        bus.ppu = ppu.memory();

        var apu = try APU.init(allocator);
        bus.apu = apu.memory();

        const input = try Input.init(allocator, bus.memory());
        bus.input = input.memory();

        const timer = try Timer.init(allocator, bus.memory());
        bus.timer = timer.memory();

        const instance = try allocator.create(Self);

        instance.* = .{
            .allocator = allocator,
            .cpu = undefined,
            .timer = timer,
            .ppu = ppu,
            .apu = apu,
            .bus = bus,
            .input = input,
            .mapper = mapper,
            .cartridge = cartridge,
            .clock = .{ .handler = instance },
            .rtc = rtc,
        };

        instance.cpu = .{
            .memory = bus.memory(),
            .double_speed = instance.clock.proxy(),
        };

        Gamebob.resetGame(instance);
        instance.initTexture();
        return instance;
    }

    pub fn deinit(self: *Self) void {
        self.deinitTexture();
        self.ppu.deinit();
        self.apu.deinit();
        self.cartridge.deinit();
        self.mapper.deinit();
        self.bus.deinit();
        self.timer.deinit();
        self.input.deinit();
        self.allocator.destroy(self);
    }

    fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn handleCPUCycle(self: *Self) void {
        const div_divider: u8 = if (self.clock.double_speed) 0x20 else 0x10;
        const div_apu = self.timer.counter.div & div_divider;

        self.input.process();
        self.cpu.process();

        if (self.cpu.mode == .switching or self.cpu.mode == .stop) {
            self.timer.counter = @bitCast(@as(u14, 0));
        }

        self.timer.process();
        if (div_apu > 0 and (self.timer.counter.div & div_divider) == 0) {
            self.apu.divTick();
            if (self.rtc) |*rtc| rtc.tick();
        }
    }

    pub fn handlePPUCycle(self: *Self) void {
        self.ppu.process();
        if (self.ppu.hdma_cpu_cycles > 0) {
            self.cpu.cycle_counter += (self.ppu.hdma_cpu_cycles * @as(u16, if (self.clock.double_speed) 2 else 1));
            self.ppu.hdma_cpu_cycles = 0;
        }
    }

    pub fn handleAPUCycle(self: *Self) void {
        self.apu.process();
    }

    pub fn resetGame(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        self.clock.reset();
        self.timer.reset();
        self.ppu.reset();
        self.apu.reset();
        self.cpu.reset();
        self.bus.reset();

        // initial state after boot ROM
        if (self.cartridge.dmg_mode) {
            self.cpu.de = @bitCast(@as(u16, 0x0008));
            if (self.cartridge.is_nintendo) {
                self.cpu.bc.b = self.cartridge.title_hash;
            }
            if (self.cpu.bc.b == 0x43 or self.cpu.bc.b == 0x58) {
                self.cpu.hl = @bitCast(@as(u16, 0x991a));
            } else {
                self.cpu.hl = @bitCast(@as(u16, 0x007c));
            }

            self.cpu.writeIO(.KEY0, 0x04);
            self.cpu.writeIO(.OPRI, 0x01);
            self.apu.dmg_mode = true;

            @memcpy(self.ppu.bcpd[0..8], PALETTES[self.cartridge.palette][0..8]);
            @memcpy(self.ppu.ocpd[0..16], PALETTES[self.cartridge.palette][8..]);
        } else {
            self.cpu.writeIO(.KEY0, self.cpu.read(0x143));
            self.cpu.writeIO(.OPRI, 0x00);
            self.apu.dmg_mode = false;

            @memset(&self.ppu.bcpd, 0xff);
            self.ppu.ocpd[0] = 0;
        }
    }

    pub fn pauseGame(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        _ = self;
    }

    pub fn resumeGame(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        _ = self;
    }

    pub fn saveState(ctx: *anyopaque, slot: u8) !void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var file: std.fs.File = undefined;
        if (builtin.os.tag == .emscripten) {
            const path = try std.fmt.allocPrintZ(allocator, "/saves/gb_{X}.st{d}", .{ self.cartridge.crc, slot });
            file = try std.fs.createFileAbsoluteZ(path, .{});
        } else {
            const path = try std.fmt.allocPrintZ(allocator, "gb_{X}.st{d}", .{ self.cartridge.crc, slot });
            file = try std.fs.cwd().createFileZ(path, .{});
        }
        defer file.close();

        var compressor = try std.compress.zlib.compressor(file.writer(), .{ .level = .fast });
        const writer = compressor.writer();

        var pack: c.mpack_writer_t = undefined;
        var data: [*c]u8 = undefined;
        var size: usize = undefined;
        c.mpack_writer_init_growable(&pack, &data, &size);
        c.mpack_build_map(&pack);

        c.mpack_write_cstr(&pack, "version");
        c.mpack_write_int(&pack, 1);

        c.mpack_write_cstr(&pack, "cpu");
        self.cpu.serialize(&pack);

        c.mpack_write_cstr(&pack, "ppu");
        self.ppu.serialize(&pack);

        c.mpack_write_cstr(&pack, "apu");
        self.apu.serialize(&pack);

        c.mpack_write_cstr(&pack, "input");
        self.input.serialize(&pack);

        c.mpack_write_cstr(&pack, "timer");
        self.timer.serialize(&pack);

        c.mpack_write_cstr(&pack, "clock");
        self.clock.serialize(&pack);

        c.mpack_write_cstr(&pack, "bus");
        self.bus.serialize(&pack);

        c.mpack_write_cstr(&pack, "mapper");
        self.mapper.serialize(&pack);

        c.mpack_complete_map(&pack);
        if (c.mpack_writer_destroy(&pack) != c.mpack_ok) return error.MPack;
        try writer.writeAll(data[0..size]);
        std.c.free(data);

        try compressor.finish();
    }

    pub fn loadState(ctx: *anyopaque, slot: u8) !bool {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var file: std.fs.File = undefined;
        if (builtin.os.tag == .emscripten) {
            const path = try std.fmt.allocPrintZ(allocator, "/saves/gb_{X}.st{d}", .{ self.cartridge.crc, slot });
            file = std.fs.openFileAbsoluteZ(path, .{}) catch return false;
        } else {
            const path = try std.fmt.allocPrintZ(allocator, "gb_{X}.st{d}", .{ self.cartridge.crc, slot });
            file = std.fs.cwd().openFileZ(path, .{}) catch return false;
        }
        defer file.close();

        var decompressor = std.compress.zlib.decompressor(file.reader());
        const reader = decompressor.reader();
        const data = try reader.readAllAlloc(allocator, std.math.maxInt(usize));

        var pack: c.mpack_tree_t = undefined;
        c.mpack_tree_init_data(&pack, data.ptr, data.len);
        defer if (c.mpack_tree_destroy(&pack) != c.mpack_ok) std.debug.print("mpack error\n", .{});
        c.mpack_tree_parse(&pack);
        const root = c.mpack_tree_root(&pack);
        if (c.mpack_node_int(c.mpack_node_map_cstr(root, "version")) == 1) {
            self.cpu.deserialize(c.mpack_node_map_cstr(root, "cpu"));
            self.ppu.deserialize(c.mpack_node_map_cstr(root, "ppu"));
            self.apu.deserialize(c.mpack_node_map_cstr(root, "apu"));
            self.input.deserialize(c.mpack_node_map_cstr(root, "input"));
            self.timer.deserialize(c.mpack_node_map_cstr(root, "timer"));
            self.clock.deserialize(c.mpack_node_map_cstr(root, "clock"));
            self.bus.deserialize(c.mpack_node_map_cstr(root, "bus"));
            self.mapper.deserialize(c.mpack_node_map_cstr(root, "mapper"));
        } else return false;

        return true;
    }

    pub fn persistBattery(ctx: *anyopaque) void {
        saveState(ctx, 0) catch return;
    }

    pub fn changeRegion(ctx: *anyopaque, region: Core.Region) void {
        _ = ctx;
        _ = region;
    }

    pub fn fillAudioBuffer(ctx: *anyopaque, buffer: []f32) usize {
        var mixer_buffer: [1470]i16 = [_]i16{0} ** 1470;
        const self: *@This() = @ptrCast(@alignCast(ctx));

        const left_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.apu.left_buf)));
        const right_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.apu.right_buf)));

        _ = c.blip_read_samples(left_buf, &mixer_buffer, 735, 1);
        _ = c.blip_read_samples(right_buf, &mixer_buffer[1], 735, 1);

        for (0..mixer_buffer.len) |i| {
            buffer[i] = @as(f32, @floatFromInt(mixer_buffer[i])) / 32768.0;
        }

        return 735;
    }

    pub fn render(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.clock.run(.frame);

        const left_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.apu.left_buf)));
        const right_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.apu.right_buf)));
        c.blip_end_frame(left_buf, self.clock.frame_cycles);
        c.blip_end_frame(right_buf, self.clock.frame_cycles);

        // toggle DMG palettes
        if (self.cartridge.dmg_mode and c.IsKeyPressed(c.KEY_T)) {
            self.dmg_colors +%= 1;
            if (self.dmg_colors == 3) self.dmg_colors = 0;
            if (self.dmg_colors == 0) {
                // GBC inferred palette
                @memcpy(self.ppu.bcpd[0..8], PALETTES[self.cartridge.palette][0..8]);
                @memcpy(self.ppu.ocpd[0..16], PALETTES[self.cartridge.palette][8..]);
            } else if (self.dmg_colors == 1) {
                // green
                @memcpy(self.ppu.bcpd[0..8], &[_]u8{ 0xfd, 0x67, 0x55, 0x4b, 0x2a, 0x3a, 0xa2, 0x1c });
                @memcpy(self.ppu.ocpd[0..8], self.ppu.bcpd[0..8]);
                @memcpy(self.ppu.ocpd[8..16], self.ppu.bcpd[0..8]);
            } else {
                // gray
                @memcpy(self.ppu.bcpd[0..8], &[_]u8{ 0xff, 0x7f, 0xb5, 0x56, 0x4a, 0x29, 0, 0 });
                @memcpy(self.ppu.ocpd[0..8], self.ppu.bcpd[0..8]);
                @memcpy(self.ppu.ocpd[8..16], self.ppu.bcpd[0..8]);
            }
        }

        c.UpdateTexture(self.texture.texture, @ptrCast(self.ppu.output));
    }

    pub fn core(self: *Self) Core {
        return .{
            .ptr = self,
            .game_width = self.render_width,
            .game_height = self.render_height,
            .render_width = &self.render_width,
            .render_height = &self.render_height,
            .state = .paused,
            .vtable = &.{
                .render = render,
                .getTexture = getTexture,
                .getShader = getShader,
                .resetGame = resetGame,
                .pauseGame = pauseGame,
                .resumeGame = resumeGame,
                .saveState = saveState,
                .loadState = loadState,
                .changeRegion = changeRegion,
                .fillAudioBuffer = fillAudioBuffer,
                .persistBattery = persistBattery,
                .deinit = deinitMemory,
            },
        };
    }
};
