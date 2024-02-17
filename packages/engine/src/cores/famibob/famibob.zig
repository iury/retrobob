const std = @import("std");
const builtin = @import("builtin");
const c = @import("../../c.zig");
const Core = @import("../core.zig");
const CPU = @import("../../cpus/6502/cpu.zig").CPU;
const PPU = @import("ppu.zig").PPU;
const APU = @import("apu/apu.zig").APU;
const Mixer = @import("apu/mixer.zig").Mixer;
const Input = @import("input.zig").Input;
const Clock = @import("clock.zig").Clock;
const Region = @import("../core.zig").Region;
const Cartridge = @import("cartridge.zig").Cartridge;
const MemoryBus = @import("memory_bus.zig").MemoryBus;
const Memory = @import("../../memory.zig").Memory;
const Proxy = @import("../../proxy.zig").Proxy;
const NROM = @import("mappers/nrom.zig").NROM;
const CNROM = @import("mappers/cnrom.zig").CNROM;
const AxROM = @import("mappers/axrom.zig").AxROM;
const UxROM = @import("mappers/uxrom.zig").UxROM;
const MMC1 = @import("mappers/mmc1.zig").MMC1;
const MMC2 = @import("mappers/mmc2.zig").MMC2;
const MMC3 = @import("mappers/mmc3.zig").MMC3;

pub const Mirroring = enum { horizontal, vertical, single_screen, four_screen };

pub const Famibob = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    cpu: CPU,
    ppu: *PPU,
    apu: *APU,
    mixer: *Mixer,
    input: Memory(u16, u8),
    mapper: Memory(u16, u8),
    mapper_irq: ?*bool = null,
    bus: Memory(u16, u8),
    cartridge: *Cartridge,
    region: Region = .ntsc,
    clock: Clock(Self, .ntsc),

    pub fn init(allocator: std.mem.Allocator, rom_data: []const u8) !*Self {
        const cartridge = try Cartridge.init(std.heap.c_allocator, rom_data);

        var mapper: Memory(u16, u8) = undefined;
        var mapper_irq: ?*bool = null;

        if (cartridge.mapper_id == 0) {
            var nrom = try NROM.init(std.heap.c_allocator, cartridge);
            mapper = nrom.memory();
        } else if (cartridge.mapper_id == 1) {
            var mmc1 = try MMC1.init(std.heap.c_allocator, cartridge);
            mapper = mmc1.memory();
        } else if (cartridge.mapper_id == 2) {
            var uxrom = try UxROM.init(std.heap.c_allocator, cartridge);
            mapper = uxrom.memory();
        } else if (cartridge.mapper_id == 3) {
            var cnrom = try CNROM.init(std.heap.c_allocator, cartridge);
            mapper = cnrom.memory();
        } else if (cartridge.mapper_id == 4) {
            var mmc3 = try MMC3.init(std.heap.c_allocator, cartridge);
            mapper = mmc3.memory();
            mapper_irq = &mmc3.irq_occurred;
        } else if (cartridge.mapper_id == 7) {
            var axrom = try AxROM.init(std.heap.c_allocator, cartridge);
            mapper = axrom.memory();
        } else if (cartridge.mapper_id == 9) {
            var mmc2 = try MMC2.init(std.heap.c_allocator, cartridge);
            mapper = mmc2.memory();
        } else {
            return error.UnsupportedMapper;
        }

        var ppu = try PPU.init(allocator, mapper);
        const ppu_memory = ppu.memory();

        const mixer = try Mixer.init(allocator, .ntsc);

        var apu = try APU.init(allocator, .ntsc, mixer);
        const apu_memory = apu.memory();
        const dmc = apu.dmc.proxy();

        var input = try Input.init(allocator);
        const input_memory = input.memory();

        var bus = try MemoryBus.init(allocator, mapper, ppu_memory, apu_memory, input_memory);
        const bus_memory = bus.memory();

        const instance = try allocator.create(Self);

        instance.* = .{
            .allocator = allocator,
            .cartridge = cartridge,
            .ppu = ppu,
            .apu = apu,
            .mixer = mixer,
            .input = input_memory,
            .mapper = mapper,
            .mapper_irq = mapper_irq,
            .bus = bus_memory,
            .cpu = .{
                .memory = bus_memory,
                .dmc = dmc,
            },
            .clock = .{ .handler = instance },
        };

        instance.cpu.rst_requested = true;
        return instance;
    }

    pub fn deinit(self: *Self) void {
        self.ppu.deinit();
        self.cartridge.deinit();
        self.mapper.deinit();
        self.apu.deinit();
        self.mixer.deinit();
        self.input.deinit();
        self.bus.deinit();
        self.allocator.destroy(self);
    }

    fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn handleCPUCycle(self: *Self) void {
        if (self.ppu.nmi_requested) {
            self.ppu.nmi_requested = false;
            self.cpu.nmi_requested = true;
        }

        if (self.apu.frame_counter.irq_requested) {
            self.cpu.irq_requested = true;
        }

        if (self.apu.dmc.irq_requested) {
            self.cpu.irq_requested = true;
        }

        if (self.mapper_irq) |irq| {
            if (irq.*) {
                self.cpu.irq_requested = true;
                irq.* = false;
            }
        }

        if (self.ppu.oam_dma) |dma| {
            self.cpu.oam_address = dma << 8;
            self.cpu.oam_dma = true;
            self.ppu.oam_dma = null;
        }

        if (self.apu.dmc.transfer_requested) {
            self.apu.dmc.transfer_requested = false;
            self.cpu.dmc_address = self.apu.dmc.current_addr;
            self.cpu.dmc_dma = true;
        }

        self.cpu.process();
        self.apu.process();
    }

    pub fn handlePPUCycle(self: *Self) void {
        self.ppu.process();
    }

    pub fn resetGame(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.cpu.rst_requested = true;
        self.ppu.reset();
        self.apu.reset();
        self.clock.reset();
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

        var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var file: std.fs.File = undefined;
        if (builtin.os.tag == .emscripten) {
            const path = try std.fmt.allocPrintZ(allocator, "/data/nes_{X}.st{d}", .{ self.cartridge.crc, slot });
            file = try std.fs.createFileAbsoluteZ(path, .{});
        } else {
            const path = try std.fmt.allocPrintZ(allocator, "nes_{X}.st{d}", .{ self.cartridge.crc, slot });
            file = try std.fs.cwd().createFileZ(path, .{});
        }

        defer file.close();
        const writer = file.writer();

        const serialized_mapper = try self.mapper.jsonStringify(allocator);

        try std.json.stringify(.{
            .version = 1,
            .cpu = &self.cpu,
            .ppu = self.ppu,
            .apu = self.apu,
            .clock = &self.clock,
            .bus = try self.bus.jsonStringify(allocator),
            .mapper = serialized_mapper,
            .mapper_irq = self.mapper_irq,
        }, .{ .emit_strings_as_arrays = true }, writer);
    }

    fn parseValue(allocator: std.mem.Allocator, T: type, target: *T, value: std.json.Value) anyerror!void {
        if (T == std.mem.Allocator or T == Memory(u16, u8) or T == Proxy(u8) or T == c.blip_t) return;
        const structInfo = @typeInfo(T);
        var it = value.object.iterator();
        while (it.next()) |kv| {
            const field_name = kv.key_ptr.*;
            inline for (structInfo.Struct.fields) |field| {
                comptime {
                    if (std.mem.eql(u8, field.name, "mixer") or std.mem.eql(u8, field.name, "apu")) continue;
                }
                if (std.mem.eql(u8, field.name, field_name)) {
                    const f = @typeInfo(field.type);
                    switch (f) {
                        .Struct => {
                            try parseValue(allocator, field.type, &@field(target, field.name), kv.value_ptr.*);
                            break;
                        },
                        .Pointer => |p| {
                            switch (@typeInfo(p.child)) {
                                .Struct => {
                                    try parseValue(allocator, p.child, @field(target, field.name), kv.value_ptr.*);
                                    break;
                                },
                                else => {},
                            }
                        },
                        else => {},
                    }
                    @field(target, field.name) = try std.json.parseFromValueLeaky(field.type, allocator, kv.value_ptr.*, .{});
                    break;
                }
            }
        }
    }

    pub fn loadState(ctx: *anyopaque, slot: u8) !bool {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var file: std.fs.File = undefined;
        if (builtin.os.tag == .emscripten) {
            const path = try std.fmt.allocPrintZ(allocator, "/data/nes_{X}.st{d}", .{ self.cartridge.crc, slot });
            file = std.fs.openFileAbsoluteZ(path, .{}) catch return false;
        } else {
            const path = try std.fmt.allocPrintZ(allocator, "nes_{X}.st{d}", .{ self.cartridge.crc, slot });
            file = std.fs.cwd().openFileZ(path, .{}) catch return false;
        }

        defer file.close();
        const reader = file.reader();
        const content = try reader.readAllAlloc(allocator, std.math.maxInt(usize));

        const data = try std.json.parseFromSliceLeaky(std.json.Value, allocator, content, .{});
        if (data.object.get("version").?.integer == 1) {
            try parseValue(allocator, CPU, &self.cpu, data.object.get("cpu").?);
            try parseValue(allocator, PPU, self.ppu, data.object.get("ppu").?);
            try parseValue(allocator, APU, self.apu, data.object.get("apu").?);
            try parseValue(allocator, Clock(Self, .ntsc), &self.clock, data.object.get("clock").?);
            try self.bus.jsonParse(allocator, data.object.get("bus").?);
            try self.mapper.jsonParse(allocator, data.object.get("mapper").?);
            if (self.mapper_irq) |irq| {
                irq.* = data.object.get("mapper_irq").?.bool;
            }
            self.mixer.reset();
        } else return false;

        return true;
    }

    pub fn persistBattery(ctx: *anyopaque) void {
        saveState(ctx, 0) catch return;
    }

    pub fn changeRegion(ctx: *anyopaque, region: Region) void {
        var self: *@This() = @ptrCast(@alignCast(ctx));
        self.region = region;
        self.clock.setRegion(region);
        self.ppu.setRegion(region);
        self.apu.setRegion(region);
    }

    var mixer_buffer: [1920]i16 = [_]i16{0} ** 1920;
    pub fn fillAudioBuffer(ctx: *anyopaque, buffer: []f32, interleave: bool) usize {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        const samples = self.apu.mixer.fillAudioBuffer(mixer_buffer[0 .. buffer.len / 2]);

        if (interleave) {
            for (0..samples) |i| {
                const v = @as(f32, @floatFromInt(mixer_buffer[i])) / 32768.0;
                buffer[i * 2] = v;
                buffer[i * 2 + 1] = v;
            }
        } else {
            for (0..samples) |i| {
                buffer[i] = @as(f32, @floatFromInt(mixer_buffer[i])) / 32768.0;
            }
            @memcpy(buffer[samples .. samples * 2], buffer[0..samples]);
        }

        if (samples * 2 < buffer.len) {
            @memset(buffer[samples * 2 .. buffer.len], 0);
        }

        return samples;
    }

    pub fn render(ctx: *anyopaque) void {
        var self: *@This() = @ptrCast(@alignCast(ctx));
        self.clock.run(.frame);
        self.apu.endFrame();

        if (self.ppu.dot == 339) {
            self.clock.run(.ppu_cycle);
        }
    }

    pub fn core(self: *Self) Core {
        return .{
            .ptr = self,
            .game_width = 256,
            .game_height = 240,
            .state = .paused,
            .vtable = &.{
                .render = render,
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

test {
    _ = @import("clock.zig");
}
