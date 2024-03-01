const std = @import("std");
const IO = @import("io.zig").IO;
const Memory = @import("../../memory.zig").Memory;

// LCD Control Register
const LCDC = packed struct {
    // [DMG] BG enable; [CGB] give OBJ priority
    bg_enable: bool,
    // 0 = OBJ off; 1 = OBJ on
    obj_enable: bool,
    // 0 = 8x8; 1 = 8x16
    obj_big: bool,
    // 0 = 9800–9BFF; 1 = 9C00–9FFF
    bg_tilemap: bool,
    // 0 = 8800–97FF; 1 = 8000–8FFF
    tiledata: bool,
    // 0 = Window off; 1 = Window on
    wnd_enable: bool,
    // 0 = 9800–9BFF; 1 = 9C00–9FFF
    wnd_tilemap: bool,
    // enable rendering and interruptions
    ppu_enable: bool,
};

// OBJ Attribute Memory, a sprite
const OAM = struct {
    // OAM[0], screen + 16
    y: u8,
    // OAM[1], screen + 8
    x: u8,
    // OAM[2], tile index inside $8000-$8FFF
    index: u8,

    // OAM[3], attributes and flags
    attr: packed struct {
        // [CGB] which of OBP0–7 to use
        cgb_palette: u3,
        // [CGB] fetch tile from VRAM bank N
        bank: u1,
        // [DMG] 0 = OBP0, 1 = OBP1
        dmg_palette: u1,
        // 0 = normal, 1 = OBJ is horizontally mirrored
        flip_h: bool,
        // 0 = normal, 1 = OBJ is vertically mirrored
        flip_v: bool,
        // 0 = no, 1 = BG and Window colors 1–3 are drawn over this OBJ
        priority: bool,
    },

    // 2 bpp pattern of the current sprite's row
    pattern: [8]?u2,
};

// [CGB] BG map attributes
const BGMapAttr = packed struct {
    // which of BGP0–7 to use
    palette: u3,
    // fetch tile from VRAM bank N
    bank: u1,
    // keep for packed alignment
    unsused: u1,
    // tile is drawn horizontally mirrored
    flip_h: bool,
    // tile is drawn vertically mirrored
    flip_v: bool,
    // 0 = no; 1 = BG/Window colors 1–3 are drawn over OBJ, regardless of OBJ priority
    priority: bool,
};

pub const PPU = struct {
    allocator: std.mem.Allocator,

    // draw to a framebuffer since the LCD display can be re-enabled off-sync with the main thread's vsync
    framebuf: []u32,
    // output to the main thread
    output: []u32,
    // 8000-9FFF, CGB has a switchable bank 0/1
    vram: []u8,
    // 0 = GCB (Gameboy Color), 1 = DMG (Gameboy)
    dmg_mode: bool = true,
    // $FF4F, [CGB] VRAM bank
    vbk: u8 = 0,

    // $FF40, LCD control
    lcdc: LCDC = @bitCast(@as(u8, 0x91)),
    // $FF41, LCD status
    stat: u8 = 0x81,

    // $FF42, scroll Y
    scy: u8 = 0,
    // $FF43, scroll X
    scx: u8 = 0,
    // $FF44, current line
    ly: u8 = 143,
    // $FF45, line to compare, may generate an IRQ based on STAT
    lyc: u8 = 0,
    // internal window LY
    wly: u8 = 0,
    // $FF4A, window Y
    wy: u8 = 0,
    // $FF4B, window X
    wx: u8 = 0,
    // $FF6C, [CGB] OBJ priority mode, 0 = CGB-style priority, 1 = DMG-style priority
    opri: bool = true,

    // maximum of 40 OBJs (4 bytes per OAM)
    oam: [160]u8 = [_]u8{0} ** 160,
    // (up to) 10 OBJs for the scanline
    y_oam: [40]u8 = [_]u8{0} ** 40,
    // how many OBJs for the scanline
    oam_cnt: u8 = 0,

    // $FF55, [CGB] write = HDMA, read = how many blocks are left
    hdma5: u8 = 0xff,
    // $FF53 + $FF54, HDMA source address
    hdmas: u16 = 0,
    // $FF51 + $FF52, HDMA destination address (offset from VRAM)
    hdmad: u16 = 0x1ff0,
    // how many cycles the CPU must wait while HDMA is in progress
    hdma_cpu_cycles: u16 = 0,

    // $FF47, [DMG] BG palette
    bgp: u8 = 0xfc,
    // $FF48, [DMG] OBJ0 palette
    obp0: u8 = 0,
    // $FF49, [DMG] OBJ1 palette
    obp1: u8 = 0,
    // $FF68, [CGB] BG palette selector
    bcps: u8 = 0,
    // $FF6A, [CGB] OBJ palette selector
    ocps: u8 = 0,

    // $FF69, [CGB] BG palettes
    bcpd: [64]u8 = [_]u8{0} ** 64,
    // $FF6B, [CGB] OBJ palettes
    ocpd: [64]u8 = [_]u8{0} ** 64,

    // https://gbdev.io/pandocs/Interrupt_Sources.html#int-48--stat-interrupt
    stat_blocking: bool = false,

    // delay of 1 CPU cycle (4 PPU cycles) to trigger IRQ
    // this seems to be required for some games to boot, like Altered Space?
    stat_irq_delay: u8 = 0,
    stat_irq: u8 = 0,

    // STAT mode, 0-4
    mode: u8 = 0,
    // how many cycles mode 3 took, used to calculate mode 0 length
    mode3_length: u16 = 0,
    // idle cycle spin to simulate the PPU doing things
    cycle_counter: u16 = 0,

    bus: Memory(u16, u8),

    pub fn init(allocator: std.mem.Allocator, bus: Memory(u16, u8)) !*PPU {
        const instance = try allocator.create(PPU);
        instance.* = .{
            .allocator = allocator,
            .framebuf = try allocator.alloc(u32, 23040),
            .output = try allocator.alloc(u32, 23040),
            .vram = try allocator.alloc(u8, 0x4000),
            .bus = bus,
        };
        @memset(instance.vram, 0);
        @memset(instance.framebuf, 0);
        return instance;
    }

    pub fn deinit(self: *PPU) void {
        self.allocator.free(self.framebuf);
        self.allocator.free(self.output);
        self.allocator.free(self.vram);
        self.allocator.destroy(self);
    }

    fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return switch (address) {
            0x8000...0x9fff => blk: {
                // can't access on mode 3
                if (!self.lcdc.ppu_enable or (self.stat & 3) != 3) {
                    break :blk self.vram[@as(usize, self.vbk) * 0x2000 + (address - 0x8000)];
                } else {
                    break :blk 0xff;
                }
            },
            0xfe00...0xfe9f => blk: {
                // can't access on mode 2 or 3
                if (!self.lcdc.ppu_enable or (self.stat & 2) != 2) {
                    break :blk self.oam[address - 0xfe00];
                } else {
                    break :blk 0xff;
                }
            },
            0xff00...0xff7f => blk: {
                break :blk switch (address) {
                    @intFromEnum(IO.LCDC) => @bitCast(self.lcdc),
                    @intFromEnum(IO.STAT) => self.stat,
                    @intFromEnum(IO.SCY) => self.scy,
                    @intFromEnum(IO.SCX) => self.scx,
                    @intFromEnum(IO.LY) => self.ly,
                    @intFromEnum(IO.LYC) => self.lyc,
                    @intFromEnum(IO.BGP) => self.bgp,
                    @intFromEnum(IO.OBP0) => self.obp0,
                    @intFromEnum(IO.OBP1) => self.obp1,
                    @intFromEnum(IO.WY) => self.wy,
                    @intFromEnum(IO.WX) => self.wx,
                    @intFromEnum(IO.OPRI) => if (self.dmg_mode or self.opri) 0xff else 0xfe,
                    @intFromEnum(IO.KEY0) => if (self.dmg_mode) 0xff else 0xc0,
                    @intFromEnum(IO.VBK) => if (self.dmg_mode) 0xff else 0xfe | self.vbk,
                    @intFromEnum(IO.HDMA5) => if (self.dmg_mode) 0xff else self.hdma5,
                    @intFromEnum(IO.BCPS) => if (self.dmg_mode) 0xff else self.bcps,
                    @intFromEnum(IO.OCPS) => if (self.dmg_mode) 0xff else self.ocps,
                    @intFromEnum(IO.BCPD) => {
                        // can't access on mode 3
                        if (!self.dmg_mode and (!self.lcdc.ppu_enable or (self.stat & 3) != 3)) {
                            break :blk self.bcpd[self.bcps & 0x3f];
                        } else {
                            break :blk 0xff;
                        }
                    },
                    @intFromEnum(IO.OCPD) => {
                        // can't access on mode 3
                        if (!self.dmg_mode and (!self.lcdc.ppu_enable or (self.stat & 3) != 3)) {
                            break :blk self.ocpd[self.ocps & 0x3f];
                        } else {
                            break :blk 0xff;
                        }
                    },
                    else => 0xff,
                };
            },
            else => 0,
        };
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        switch (address) {
            0x8000...0x9fff => {
                // can't access on mode 3
                if (!self.lcdc.ppu_enable or (self.stat & 3) != 3) {
                    self.vram[@as(usize, self.vbk) * 0x2000 + (address - 0x8000)] = value;
                }
            },
            0xfe00...0xfe9f => {
                // can't access on mode 2 or 3
                if (!self.lcdc.ppu_enable or (self.stat & 2) != 2) {
                    self.oam[address - 0xfe00] = value;
                }
            },
            0xff00...0xff7f => {
                switch (address) {
                    @intFromEnum(IO.LCDC) => self.lcdc = @bitCast(value),
                    @intFromEnum(IO.STAT) => {
                        self.stat = 0x80 | (value & 0x78) | //
                            @as(u8, if (self.ly == self.lyc) 4 else 0) | //
                            @as(u8, if (self.lcdc.ppu_enable) self.mode else 0);
                    },
                    @intFromEnum(IO.SCY) => self.scy = value,
                    @intFromEnum(IO.SCX) => self.scx = value,
                    @intFromEnum(IO.LYC) => self.lyc = value,
                    @intFromEnum(IO.DMA) => {
                        for (0..160) |i| {
                            self.oam[i] = self.bus.read(@intCast((@as(u16, value) << 8) + i));
                        }
                    },
                    @intFromEnum(IO.BGP) => self.bgp = value,
                    @intFromEnum(IO.OBP0) => self.obp0 = value,
                    @intFromEnum(IO.OBP1) => self.obp1 = value,
                    @intFromEnum(IO.WY) => self.wy = value,
                    @intFromEnum(IO.WX) => self.wx = value,
                    @intFromEnum(IO.OPRI) => self.opri = (value & 1) == 1,
                    @intFromEnum(IO.KEY0) => self.dmg_mode = value != 0x80 and value != 0xc0,
                    @intFromEnum(IO.VBK) => self.vbk = value & 1,
                    @intFromEnum(IO.HDMA1) => {
                        self.hdmas &= 0xf0;
                        self.hdmas |= @as(u16, value) << 8;

                        // filter illegal range
                        switch (self.hdmas) {
                            0xe000...0xffff => {
                                self.hdmas %= 0x2000;
                                self.hdmas += 0xa000;
                            },
                            else => {},
                        }
                    },
                    @intFromEnum(IO.HDMA2) => {
                        self.hdmas &= 0xff00;
                        self.hdmas |= value & 0xf0;
                    },
                    @intFromEnum(IO.HDMA3) => {
                        self.hdmad &= 0xf0;
                        self.hdmad |= @as(u16, value & 0x1f) << 8;
                    },
                    @intFromEnum(IO.HDMA4) => {
                        self.hdmad &= 0x1f00;
                        self.hdmad |= value & 0xf0;
                    },
                    @intFromEnum(IO.HDMA5) => {
                        // https://gbdev.io/pandocs/CGB_Registers.html#ff55--hdma5-cgb-mode-only-vram-dma-lengthmodestart
                        if ((self.hdma5 & 0x80) == 0) {
                            if ((value & 0x80) == 0) {
                                self.hdma5 |= 0x80;
                            } else {
                                self.hdma5 = value & 0x7f;
                            }
                        } else {
                            if (value & 0x80 == 0) {
                                const s = self.hdmas;
                                const d = self.hdmad;
                                self.hdma5 = value;
                                while (self.hdma5 != 0xff) {
                                    if (!self.hdma()) break;
                                }
                                self.hdmas = s;
                                self.hdmad = d;
                            } else {
                                self.hdma5 = value & 0x7f;
                                if (!self.lcdc.ppu_enable or self.mode == 0) {
                                    _ = self.hdma();
                                }
                            }
                        }
                    },
                    @intFromEnum(IO.BCPD) => {
                        if (!self.dmg_mode) {
                            // can't access on mode 3
                            if (!self.lcdc.ppu_enable or (self.stat & 3) != 3) self.bcpd[self.bcps & 0x3f] = value;
                            if (self.bcps & 0x80 > 0) self.bcps = (self.bcps + 1) & 0xbf;
                        }
                    },
                    @intFromEnum(IO.OCPD) => {
                        if (!self.dmg_mode) {
                            // can't access on mode 3
                            if (!self.lcdc.ppu_enable or (self.stat & 3) != 3) self.ocpd[self.ocps & 0x3f] = value;
                            if (self.ocps & 0x80 > 0) self.ocps = (self.ocps + 1) & 0xbf;
                        }
                    },
                    @intFromEnum(IO.BCPS) => self.bcps = value & 0xbf,
                    @intFromEnum(IO.OCPS) => self.ocps = value & 0xbf,
                    else => {},
                }
            },
            else => {},
        }
    }

    fn hdma(self: *PPU) bool {
        self.hdma5 -%= 1;
        self.hdma_cpu_cycles += 8;
        for (0..16) |_| {
            self.vram[@as(usize, self.vbk) * 0x2000 + self.hdmad] = self.bus.read(self.hdmas);
            self.hdmas +%= 1;
            self.hdmad += 1;

            // "if the transfer's destination address overflows, the transfer stops prematurely"
            if (self.hdmad == 0x2000) {
                self.hdmad = 0;
                self.hdma5 |= 0x80;
                return false;
            }
        }
        return true;
    }

    fn hblank(self: *PPU) u16 {
        if (self.lcdc.ppu_enable and self.hdma5 < 0x80) {
            _ = self.hdma();
        }
        return 376 - self.mode3_length;
    }

    fn vblank(self: *PPU) u16 {
        self.wly = 0;
        return 456;
    }

    fn oamscan(self: *PPU) u16 {
        self.oam_cnt = 0;
        if (self.lcdc.obj_enable) {
            for (0..40) |i| {
                const y: i16 = @intCast(@as(u16, self.oam[i * 4]));
                const sy1: i16 = y - 16;
                const sy2: i16 = y - @as(i16, if (self.lcdc.obj_big) 0 else 8);
                if (self.ly >= sy1 and self.ly < sy2) {
                    @memcpy(self.y_oam[self.oam_cnt * 4 .. (self.oam_cnt + 1) * 4], self.oam[i * 4 .. (i + 1) * 4]);
                    self.oam_cnt += 1;
                    if (self.oam_cnt == 10) break;
                }
            }
        }
        return 80;
    }

    fn loadSprites(self: *PPU) std.meta.Tuple(&.{ [160]?u32, [160]bool }) {
        var colors: [160]?u32 = [_]?u32{null} ** 160;
        var priorities: [160]bool = [_]bool{true} ** 160;
        var opaque_sprite: [160]?usize = [_]?usize{null} ** 160;
        var sprites: [10]OAM = undefined;

        for (0..self.oam_cnt) |i| {
            var sprite: OAM = .{
                .y = self.y_oam[i * 4],
                .x = self.y_oam[i * 4 + 1],
                .index = self.y_oam[i * 4 + 2],
                .attr = @bitCast(self.y_oam[i * 4 + 3]),
                .pattern = [_]?u2{null} ** 8,
            };

            var addr: u16 = if (!self.dmg_mode and sprite.attr.bank == 1) 0x2000 else 0;
            {
                var idx = sprite.index;
                if (!sprite.attr.flip_v) {
                    if (self.lcdc.obj_big) idx &= 0xfe;
                    addr += (@as(u16, idx) * 16) + ((16 - (sprite.y - self.ly)) << 1);
                } else {
                    if (self.lcdc.obj_big) idx &= 0xfe;
                    addr += (@as(u16, idx) * 16) + (((sprite.y - self.ly) - @as(u16, if (self.lcdc.obj_big) 1 else 9)) << 1);
                }
            }

            const p1 = self.vram[addr];
            const p2 = self.vram[addr + 1];

            for (0..8) |j| {
                const x: u3 = 7 - @as(u3, @intCast(j));
                var color_idx: u3 = @as(u3, @intCast((p1 >> x) & 1));
                color_idx |= @as(u3, @intCast((p2 >> x) & 1)) << 1;
                if (color_idx > 0) {
                    if (self.dmg_mode) {
                        const obp = if (sprite.attr.dmg_palette == 0) self.obp0 else self.obp1;
                        sprite.pattern[j] = @intCast((obp >> (color_idx << 1)) & 3);
                    } else {
                        sprite.pattern[j] = @intCast(color_idx);
                    }
                }
            }

            if (sprite.attr.flip_h) {
                std.mem.reverse(?u2, &sprite.pattern);
            }

            for (0..8) |j| {
                const x_pos: isize = @as(isize, @intCast(@as(usize, sprite.x))) - 8 + @as(isize, @intCast(j));
                if (x_pos >= 0 and x_pos < 160) {
                    const x: usize = @bitCast(x_pos);

                    // DMG = the smaller the X coordinate, the higher the priority
                    // CGB = only the object's location in OAM determines its priority
                    if (opaque_sprite[x]) |o| {
                        if (self.dmg_mode) {
                            const other = sprites[o];
                            if (sprite.x >= other.x) continue;
                        } else continue;
                    }

                    if (sprite.pattern[j]) |color| {
                        const c = @as(usize, color) * 2;
                        const palette: usize = if (self.dmg_mode) (if (sprite.attr.dmg_palette == 0) 0 else 8) else @as(usize, sprite.attr.cgb_palette) * 8;
                        colors[x] = rgbcolor(self.ocpd[palette + c], self.ocpd[palette + c + 1]);
                        priorities[x] = sprite.attr.priority;
                        opaque_sprite[x] = i;
                    }
                }
            }

            sprites[i] = sprite;
        }

        return .{ colors, priorities };
    }

    fn fetchTile(self: *PPU, window: bool, lx: u8, ly: u8) std.meta.Tuple(&.{ [8]u2, BGMapAttr }) {
        const base_tilemap = if (window) self.lcdc.wnd_tilemap else self.lcdc.bg_tilemap;

        var index: u8 = 0;
        var attr: BGMapAttr = undefined;
        {
            const y: u16 = ly / 8;
            const x: u16 = lx / 8;
            const mapaddr = @as(u16, if (base_tilemap) 0x1c00 else 0x1800) | (y << 5) | x;
            index = self.vram[mapaddr];
            attr = @bitCast(self.vram[mapaddr + 0x2000]);
        }

        var addr: u16 = if (!self.dmg_mode and attr.bank == 1) 0x2000 else 0;
        {
            var idx: u16 = index;
            if (!self.lcdc.tiledata and idx < 0x80) idx += 0x100;
            addr += idx * 0x10;
            const y = ly % 8;
            if (!self.dmg_mode and attr.flip_v) {
                addr += (7 - y) * 2;
            } else {
                addr += y * 2;
            }
        }

        var pattern: [8]u2 = [_]u2{0} ** 8;
        {
            const p1 = self.vram[addr];
            const p2 = self.vram[addr + 1];

            for (0..8) |i| {
                const x: u3 = 7 - @as(u3, @intCast(i));
                var color_idx: u3 = @as(u3, @intCast((p1 >> x) & 1));
                color_idx |= @as(u3, @intCast((p2 >> x) & 1)) << 1;
                pattern[i] = @intCast(color_idx);
            }
        }

        if (!self.dmg_mode and attr.flip_h) {
            std.mem.reverse(u2, &pattern);
        }

        return .{ pattern, attr };
    }

    fn rgbcolor(cl: u8, ch: u8) u32 {
        const color: u16 = (@as(u16, ch) << 8) | cl;
        const r: u32 = ((color & 0x1f) << 3) | (((color & 0x1f) >> 2) & 7);
        const g: u32 = (((color >> 5) & 0x1f) << 3) | ((((color >> 5) & 0x1f) >> 2) & 7);
        const b: u32 = (((color >> 10) & 0x1f) << 3) | ((((color >> 10) & 0x1f) >> 2) & 7);
        return 0xff000000 | (b << 16) | (g << 8) | r;
    }

    fn draw(self: *PPU) !u16 {
        self.mode3_length = 172;
        if (!self.lcdc.ppu_enable) return self.mode3_length;
        self.mode3_length += (self.scx % 8) + (self.oam_cnt * 6);

        var bgattr: BGMapAttr = undefined;
        var wndattr: BGMapAttr = undefined;
        var wnd_draw: bool = false;
        var wlx: u8 = 0;

        var bg_pattern: std.fifo.LinearFifo(u2, .{ .Static = 8 }) = std.fifo.LinearFifo(u2, .{ .Static = 8 }).init();
        {
            const tile = self.fetchTile(false, self.scx, self.ly +% self.scy);
            try bg_pattern.write(&tile.@"0");
            bgattr = tile.@"1";
            for (0..(self.scx % 8)) |_| _ = bg_pattern.readItem();
        }

        var wnd_pattern: std.fifo.LinearFifo(u2, .{ .Static = 8 }) = std.fifo.LinearFifo(u2, .{ .Static = 8 }).init();
        {
            const tile = self.fetchTile(true, wlx, self.wly);
            try wnd_pattern.write(&tile.@"0");
            wndattr = tile.@"1";
            if (self.wx < 7) {
                for (0..(7 - self.wx)) |_| _ = wnd_pattern.readItem();
            }
        }

        var sprite_colors: [160]?u32 = undefined;
        var priorities: [160]bool = undefined;
        {
            const v = self.loadSprites();
            sprite_colors = v.@"0";
            priorities = v.@"1";
        }

        for (0..160) |lx| {
            const pos: usize = @as(usize, self.ly) * 160 + lx;
            var color: u2 = 0;
            var out_color: u32 = 0;

            if (!self.dmg_mode or self.lcdc.bg_enable) {
                color = bg_pattern.readItem() orelse blk: {
                    const tile = self.fetchTile(false, @as(u8, @intCast(lx)) +% self.scx, self.ly +% self.scy);
                    try bg_pattern.write(&tile.@"0");
                    bgattr = tile.@"1";
                    break :blk bg_pattern.readItem().?;
                };

                if (self.lcdc.wnd_enable) {
                    if (self.ly >= self.wy and ((self.wx < 8) or (lx >= self.wx - 7))) {
                        if (!wnd_draw) {
                            wnd_draw = true;
                            self.mode3_length += 6;
                        }
                        color = wnd_pattern.readItem() orelse blk: {
                            wlx += 8;
                            const tile = self.fetchTile(true, wlx, self.wly);
                            try wnd_pattern.write(&tile.@"0");
                            wndattr = tile.@"1";
                            break :blk wnd_pattern.readItem().?;
                        };
                        bgattr = wndattr;
                    }
                }
            }

            out_color = blk: {
                if (self.dmg_mode) {
                    const c = @as(usize, @intCast((self.bgp >> (@as(u3, color) << 1)) & 3)) * 2;
                    break :blk rgbcolor(self.bcpd[c], self.bcpd[c + 1]);
                } else {
                    const c = @as(usize, color) * 2;
                    const palette: usize = @as(usize, bgattr.palette) * 8;
                    break :blk rgbcolor(self.bcpd[palette + c], self.bcpd[palette + c + 1]);
                }
            };

            if (sprite_colors[lx]) |sc| {
                if (self.dmg_mode) {
                    if (color == 0 or !priorities[lx]) {
                        out_color = sc;
                    }
                } else {
                    if (!self.lcdc.bg_enable or color == 0 or (!bgattr.priority and !priorities[lx])) {
                        out_color = sc;
                    }
                }
            }

            self.framebuf[pos] = out_color;
        }

        if (wnd_draw) self.wly += 1;

        return self.mode3_length;
    }

    fn update_stat(self: *PPU) void {
        self.stat = 0x80 | (self.stat & 0x78) | @as(u8, if (self.ly == self.lyc) 4 else 0) | @as(u8, if (self.lcdc.ppu_enable) self.mode else 0);

        const prev_int = self.stat_blocking;
        self.stat_blocking = false;

        if (self.lcdc.ppu_enable) {
            if (self.mode == 0 and (self.stat & 0x08) > 0) self.stat_blocking = true;
            if (self.mode == 1 and (self.stat & 0x10) > 0) self.stat_blocking = true;
            if (self.mode == 2 and (self.stat & 0x20) > 0) self.stat_blocking = true;
            if (self.ly == self.lyc and (self.stat & 0x40) > 0) self.stat_blocking = true;
        }

        if (self.stat_blocking and !prev_int) {
            self.stat_irq |= 2;
            self.stat_irq_delay = 5;
        }
    }

    pub fn process(self: *PPU) void {
        // LY=LYC must be constantly checked
        self.update_stat();

        self.stat_irq_delay -|= 1;
        if (self.stat_irq_delay == 1) {
            self.bus.write(@intFromEnum(IO.IF), self.bus.read(@intFromEnum(IO.IF)) | self.stat_irq);
            self.stat_irq = 0;
        }

        self.cycle_counter -|= 1;
        if (self.cycle_counter > 0) return;

        if (self.mode < 2) {
            self.ly = (self.ly + 1) % 154;
        }

        if (self.ly < 144) {
            self.mode = (self.mode + 1) % 4;
            if (self.mode == 1) self.mode = 2;
        } else if (self.ly == 144) {
            self.mode = 1;

            // VBlank INT
            if (self.lcdc.ppu_enable) {
                self.stat_irq |= 1;
                self.stat_irq_delay = 5;

                // flush the frame buffer
                @memcpy(self.output, self.framebuf);
            }
        }

        self.update_stat();

        self.cycle_counter = switch (self.mode) {
            0 => self.hblank(),
            1 => self.vblank(),
            2 => self.oamscan(),
            3 => self.draw() catch unreachable,
            else => 0,
        };
    }

    pub fn reset(self: *PPU) void {
        self.oam_cnt = 0;
        self.ly = 143;
        self.lyc = 0;
        self.wly = 0;
        self.scx = 0;
        self.scy = 0;
        self.bgp = 0xfc;
        self.obp0 = 0;
        self.obp1 = 0;
        self.wy = 0;
        self.wx = 0;
        self.vbk = 0;
        self.mode = 0;
        self.stat = 0x81;
        self.stat_blocking = false;
        self.mode3_length = 0;
        self.cycle_counter = 0;
        self.stat_irq = 0;
        self.stat_irq_delay = 0;
        self.lcdc = @bitCast(@as(u8, 0x91));
        self.bcps = 0;
        self.ocps = 0;
        self.opri = true;
        self.dmg_mode = true;
        self.hdma5 = 0xff;
        self.hdmad = 0x1ff0;
        self.hdmas = 0;
        self.hdma_cpu_cycles = 0;
    }

    pub fn memory(self: *PPU) Memory(u16, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinitMemory,
            },
        };
    }

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("vram");
        try jw.write(self.vram);
        try jw.objectField("dmg_mode");
        try jw.write(self.dmg_mode);
        try jw.objectField("vbk");
        try jw.write(self.vbk);

        try jw.objectField("lcdc");
        try jw.beginObject();
        try jw.objectField("bg_enable");
        try jw.write(self.lcdc.bg_enable);
        try jw.objectField("obj_enable");
        try jw.write(self.lcdc.obj_enable);
        try jw.objectField("obj_big");
        try jw.write(self.lcdc.obj_big);
        try jw.objectField("bg_tilemap");
        try jw.write(self.lcdc.bg_tilemap);
        try jw.objectField("tiledata");
        try jw.write(self.lcdc.tiledata);
        try jw.objectField("wnd_enable");
        try jw.write(self.lcdc.wnd_enable);
        try jw.objectField("wnd_tilemap");
        try jw.write(self.lcdc.wnd_tilemap);
        try jw.objectField("ppu_enable");
        try jw.write(self.lcdc.ppu_enable);
        try jw.endObject();

        try jw.objectField("stat");
        try jw.write(self.stat);

        try jw.objectField("scy");
        try jw.write(self.scy);
        try jw.objectField("scx");
        try jw.write(self.scx);
        try jw.objectField("ly");
        try jw.write(self.ly);
        try jw.objectField("lyc");
        try jw.write(self.lyc);
        try jw.objectField("wly");
        try jw.write(self.wly);
        try jw.objectField("wy");
        try jw.write(self.wy);
        try jw.objectField("wx");
        try jw.write(self.wx);
        try jw.objectField("opri");
        try jw.write(self.opri);

        try jw.objectField("oam");
        try jw.write(self.oam);

        try jw.objectField("hdma5");
        try jw.write(self.hdma5);
        try jw.objectField("hdmas");
        try jw.write(self.hdmas);
        try jw.objectField("hdmad");
        try jw.write(self.hdmad);

        try jw.objectField("bgp");
        try jw.write(self.bgp);
        try jw.objectField("obp0");
        try jw.write(self.obp0);
        try jw.objectField("obp1");
        try jw.write(self.obp1);
        try jw.objectField("bcps");
        try jw.write(self.bcps);
        try jw.objectField("ocps");
        try jw.write(self.ocps);
        try jw.objectField("bcpd");
        try jw.write(self.bcpd);
        try jw.objectField("ocpd");
        try jw.write(self.ocpd);

        try jw.objectField("stat_blocking");
        try jw.write(self.stat_blocking);
        try jw.objectField("stat_irq_delay");
        try jw.write(self.stat_irq_delay);
        try jw.objectField("stat_irq");
        try jw.write(self.stat_irq);

        try jw.objectField("mode");
        try jw.write(self.mode);
        try jw.objectField("mode3_length");
        try jw.write(self.mode3_length);
        try jw.objectField("cycle_counter");
        try jw.write(self.cycle_counter);
        try jw.endObject();
    }

    pub fn jsonParse(self: *PPU, value: std.json.Value) void {
        @memset(self.vram, 0);
        for (value.object.get("vram").?.array.items, 0..) |v, i| {
            self.vram[i] = @intCast(v.integer);
        }

        @memset(&self.oam, 0);
        for (value.object.get("oam").?.array.items, 0..) |v, i| {
            self.oam[i] = @intCast(v.integer);
        }

        @memset(&self.bcpd, 0);
        for (value.object.get("bcpd").?.array.items, 0..) |v, i| {
            self.bcpd[i] = @intCast(v.integer);
        }

        @memset(&self.ocpd, 0);
        for (value.object.get("ocpd").?.array.items, 0..) |v, i| {
            self.ocpd[i] = @intCast(v.integer);
        }

        self.dmg_mode = value.object.get("dmg_mode").?.bool;
        self.vbk = @intCast(value.object.get("vbk").?.integer);

        const lcdc = value.object.get("lcdc").?;
        self.lcdc.bg_enable = lcdc.object.get("bg_enable").?.bool;
        self.lcdc.obj_enable = lcdc.object.get("obj_enable").?.bool;
        self.lcdc.obj_big = lcdc.object.get("obj_big").?.bool;
        self.lcdc.bg_tilemap = lcdc.object.get("bg_tilemap").?.bool;
        self.lcdc.tiledata = lcdc.object.get("tiledata").?.bool;
        self.lcdc.wnd_enable = lcdc.object.get("wnd_enable").?.bool;
        self.lcdc.wnd_tilemap = lcdc.object.get("wnd_tilemap").?.bool;
        self.lcdc.ppu_enable = lcdc.object.get("ppu_enable").?.bool;

        self.stat = @intCast(value.object.get("stat").?.integer);

        self.scy = @intCast(value.object.get("scy").?.integer);
        self.scx = @intCast(value.object.get("scx").?.integer);
        self.ly = @intCast(value.object.get("ly").?.integer);
        self.lyc = @intCast(value.object.get("lyc").?.integer);
        self.wly = @intCast(value.object.get("wly").?.integer);
        self.wy = @intCast(value.object.get("wy").?.integer);
        self.wx = @intCast(value.object.get("wx").?.integer);
        self.opri = value.object.get("opri").?.bool;

        self.hdma5 = @intCast(value.object.get("hdma5").?.integer);
        self.hdmas = @intCast(value.object.get("hdmas").?.integer);
        self.hdmad = @intCast(value.object.get("hdmad").?.integer);

        self.bgp = @intCast(value.object.get("bgp").?.integer);
        self.obp0 = @intCast(value.object.get("obp0").?.integer);
        self.obp1 = @intCast(value.object.get("obp1").?.integer);
        self.bcps = @intCast(value.object.get("bcps").?.integer);
        self.ocps = @intCast(value.object.get("ocps").?.integer);

        self.stat_blocking = value.object.get("stat_blocking").?.bool;
        self.stat_irq_delay = @intCast(value.object.get("stat_irq_delay").?.integer);
        self.stat_irq = @intCast(value.object.get("stat_irq").?.integer);

        self.mode = @intCast(value.object.get("mode").?.integer);
        self.mode3_length = @intCast(value.object.get("mode3_length").?.integer);
        self.cycle_counter = @intCast(value.object.get("cycle_counter").?.integer);
    }
};
