const std = @import("std");
const builtin = @import("builtin");
const c = @import("../../c.zig");

const Core = @import("../core.zig");
const CPU = @import("cpu.zig").CPU;
const PPU = @import("ppu.zig").PPU;
const APU = @import("apu/apu.zig").APU;
const Input = @import("input.zig").Input;
const Clock = @import("clock.zig").Clock;
const DMA = @import("dma.zig").DMA;
const Proxy = @import("../../proxy.zig").Proxy;
const Memory = @import("../../memory.zig").Memory;
const MemoryBus = @import("memory_bus.zig").MemoryBus;
const Cartridge = @import("cartridge.zig").Cartridge;
const LoROM = @import("mappers/lorom.zig").LoROM;
const HiROM = @import("mappers/hirom.zig").HiROM;
const ExHiROM = @import("mappers/exhirom.zig").ExHiROM;

pub const Superbob = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    cpu: CPU,
    apu: *APU,
    ppu: *PPU,
    input: *Input,
    dma: *DMA,
    bus: *MemoryBus,
    mapper: Memory(u24, u8),
    clock: Clock(Self),
    cartridge: *Cartridge,

    texture: c.RenderTexture2D = undefined,
    render_width: f32 = 256,
    render_height: f32 = 224,

    fn initTexture(self: *Self) void {
        self.texture = c.LoadRenderTexture(@intFromFloat(512), @intFromFloat(478));
    }

    fn deinitTexture(self: *Self) void {
        c.UnloadRenderTexture(self.texture);
    }

    pub fn getTexture(ctx: *anyopaque) c.Texture {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return self.texture.texture;
    }

    pub fn getShader(ctx: *anyopaque, source: c.Rectangle, dest: c.Rectangle) ?c.Shader {
        _ = ctx;
        _ = dest;
        _ = source;
        return null;
    }

    pub fn init(allocator: std.mem.Allocator, rom_data: []const u8) !*Self {
        const cartridge = try Cartridge.init(allocator, rom_data);

        var bus = try MemoryBus.init(allocator);
        var mapper: Memory(u24, u8) = undefined;

        switch (cartridge.mapper) {
            .lorom => {
                var lorom = try LoROM.init(allocator, cartridge, &bus.openbus);
                mapper = lorom.memory();
            },
            .hirom => {
                var hirom = try HiROM.init(allocator, cartridge, &bus.openbus);
                mapper = hirom.memory();
            },
            .exhirom => {
                var exhirom = try ExHiROM.init(allocator, cartridge, &bus.openbus);
                mapper = exhirom.memory();
            },
            .unknown => {},
        }

        bus.mapper = mapper;

        const instance = try allocator.create(Self);

        var dma = try DMA.init(allocator, bus.memory(), &bus.openbus, &instance.clock.dma_offset_counter);
        bus.dma = dma.memory();

        var input = try Input.init(allocator, bus.memory());
        bus.input = input.memory();

        var ppu = try PPU.init(allocator, &bus.openbus, input, dma, &instance.render_width, &instance.render_height);
        bus.ppu = ppu.memory();

        var apu = try APU.init(allocator);
        bus.apu = apu.memory();

        instance.* = .{
            .allocator = allocator,
            .cpu = undefined,
            .ppu = ppu,
            .apu = apu,
            .bus = bus,
            .dma = dma,
            .input = input,
            .mapper = mapper,
            .cartridge = cartridge,
            .clock = .{ .handler = instance },
        };

        instance.clock.setRegion(cartridge.region);

        instance.cpu = .{
            .memory = bus.memory(),
            .memsel = &instance.bus.memsel,
        };

        Superbob.resetGame(instance);
        instance.initTexture();
        return instance;
    }

    pub fn deinit(self: *Self) void {
        self.deinitTexture();
        self.ppu.deinit();
        self.apu.deinit();
        self.dma.deinit();
        self.cartridge.deinit();
        self.mapper.deinit();
        self.bus.deinit();
        self.input.deinit();
        self.allocator.destroy(self);
    }

    fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn handleCPUCycle(self: *Self) void {
        self.dma.process();
        self.cpu.halt = self.dma.cycle_counter > 0;
        self.cpu.process();
    }

    pub fn handlePPUCycle(self: *Self) void {
        self.ppu.process();
        self.cpu.nmi_requested = self.ppu.nmitimen.nmi_enable and self.ppu.rdnmi.vblank;
        self.cpu.irq_requested = self.ppu.irq_requested;
        self.cpu.cycle_counter += self.ppu.extra_cpu_cycles;
        self.ppu.extra_cpu_cycles = 0;
    }

    pub fn handleAPUCycle(self: *Self) void {
        self.apu.process();
    }

    pub fn resetGame(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.clock.reset();
        self.dma.reset();
        self.ppu.reset();
        self.apu.reset();
        self.cpu.reset();
        self.bus.reset();
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
            const path = try std.fmt.allocPrintZ(allocator, "/saves/sfc_{X}.st{d}", .{ self.cartridge.crc, slot });
            file = try std.fs.createFileAbsoluteZ(path, .{});
        } else {
            const path = try std.fmt.allocPrintZ(allocator, "sfc_{X}.st{d}", .{ self.cartridge.crc, slot });
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

        c.mpack_write_cstr(&pack, "clock");
        self.clock.serialize(&pack);

        c.mpack_write_cstr(&pack, "dma");
        self.dma.serialize(&pack);

        c.mpack_write_cstr(&pack, "bus");
        self.bus.serialize(&pack);

        c.mpack_write_cstr(&pack, "mapper");
        self.mapper.serialize(&pack);

        c.mpack_write_cstr(&pack, "render_width");
        c.mpack_write_float(&pack, self.render_width);

        c.mpack_write_cstr(&pack, "render_height");
        c.mpack_write_float(&pack, self.render_height);

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
            const path = try std.fmt.allocPrintZ(allocator, "/saves/sfc_{X}.st{d}", .{ self.cartridge.crc, slot });
            file = std.fs.openFileAbsoluteZ(path, .{}) catch return false;
        } else {
            const path = try std.fmt.allocPrintZ(allocator, "sfc_{X}.st{d}", .{ self.cartridge.crc, slot });
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
            self.clock.deserialize(c.mpack_node_map_cstr(root, "clock"));
            self.dma.deserialize(c.mpack_node_map_cstr(root, "dma"));
            self.bus.deserialize(c.mpack_node_map_cstr(root, "bus"));
            self.mapper.deserialize(c.mpack_node_map_cstr(root, "mapper"));
            self.render_width = c.mpack_node_float(c.mpack_node_map_cstr(root, "render_width"));
            self.render_height = c.mpack_node_float(c.mpack_node_map_cstr(root, "render_height"));
        } else return false;

        return true;
    }

    pub fn persistBattery(ctx: *anyopaque) void {
        saveState(ctx, 0) catch return;
    }

    pub fn changeRegion(ctx: *anyopaque, region: Core.Region) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.clock.setRegion(region);
        self.ppu.stat78.mode = if (region == .ntsc) .ntsc else .pal;
    }

    pub fn fillAudioBuffer(ctx: *anyopaque, buffer: []f32) usize {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        var mixer_buffer: [1764]i16 = [_]i16{0} ** 1764;
        const len: usize = if (self.cartridge.region == .ntsc) 735 else 882;

        const left_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.apu.dsp.left_buf)));
        const right_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.apu.dsp.right_buf)));

        _ = c.blip_read_samples(left_buf, &mixer_buffer, @intCast(len), 1);
        _ = c.blip_read_samples(right_buf, &mixer_buffer[1], @intCast(len), 1);

        for (0..len * 2) |i| {
            buffer[i] = @as(f32, @floatFromInt(mixer_buffer[i])) / 32768.0;
        }

        return len;
    }

    pub fn render(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.clock.run(.frame);
        c.UpdateTexture(self.texture.texture, @ptrCast(self.ppu.output));
        const left_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.apu.dsp.left_buf)));
        const right_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.apu.dsp.right_buf)));
        c.blip_end_frame(left_buf, self.apu.dsp.samples);
        c.blip_end_frame(right_buf, self.apu.dsp.samples);
        self.apu.dsp.samples = 0;
    }

    pub fn core(self: *Self) Core {
        return .{
            .ptr = self,
            .game_width = 256,
            .game_height = if (self.cartridge.region == .ntsc) 224 else 239,
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
