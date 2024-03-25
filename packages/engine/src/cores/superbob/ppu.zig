const std = @import("std");
const Memory = @import("../../memory.zig").Memory;
const Input = @import("input.zig").Input;
const DMA = @import("dma.zig").DMA;
const IO = @import("io.zig").IO;
const c = @import("../../c.zig");

pub const PPU = struct {
    allocator: std.mem.Allocator,
    framebuf: []u32,
    output: []u32,
    vram: []u16,
    cgram: []u16,
    oam: []u8,

    inidisp: INIDISP = @bitCast(@as(u8, 0x80)),
    objsel: OBJSEL = @bitCast(@as(u8, 0)),
    setini: SETINI = @bitCast(@as(u8, 0)),
    stat77: STAT77 = @bitCast(@as(u8, 1)),

    oamaddl: u8 = 0,
    oamaddh: OAMADDH = @bitCast(@as(u8, 0)),
    oamadd: u10 = 0,
    oamdata: u8 = 0,

    bgmode: BGMODE = @bitCast(@as(u8, 0x0f)),
    mosaic: MOSAIC = @bitCast(@as(u8, 0)),
    bg1sc: BGSC = @bitCast(@as(u8, 0)),
    bg2sc: BGSC = @bitCast(@as(u8, 0)),
    bg3sc: BGSC = @bitCast(@as(u8, 0)),
    bg4sc: BGSC = @bitCast(@as(u8, 0)),
    bg12nba: BG12NBA = @bitCast(@as(u8, 0)),
    bg34nba: BG34NBA = @bitCast(@as(u8, 0)),
    bg1hofs: u10 = 0,
    bg1vofs: u10 = 0,
    bg2hofs: u10 = 0,
    bg2vofs: u10 = 0,
    bg3hofs: u10 = 0,
    bg3vofs: u10 = 0,
    bg4hofs: u10 = 0,
    bg4vofs: u10 = 0,
    bgofs_latch: u8 = 0,
    bghofs_latch: u8 = 0,

    vmain: VMAIN = @bitCast(@as(u8, 0xf)),
    vmadd: u16 = 0,
    vmdata: u16 = 0,

    m7sel: M7SEL = @bitCast(@as(u8, 0)),
    m7hofs: u13 = 0,
    m7vofs: u13 = 0,
    m7a: u16 = 0,
    m7b: u16 = 0,
    m7c: u16 = 0,
    m7d: u16 = 0,
    mpy: u24 = 0,
    m7x: u13 = 0,
    m7y: u13 = 0,
    m7_latch: u8 = 0,

    cgadd: u8 = 0,
    cgdata: u8 = 0,
    cgdata_l: bool = false,

    w12sel: W12SEL = @bitCast(@as(u8, 0)),
    w34sel: W34SEL = @bitCast(@as(u8, 0)),
    wobjsel: WOBJSEL = @bitCast(@as(u8, 0)),
    wbglog: WBGLOG = @bitCast(@as(u8, 0)),
    wobjlog: WOBJLOG = @bitCast(@as(u8, 0)),
    wh0: u8 = 0,
    wh1: u8 = 0,
    wh2: u8 = 0,
    wh3: u8 = 0,

    tm: TMTS = @bitCast(@as(u8, 0)),
    ts: TMTS = @bitCast(@as(u8, 0)),
    tmw: TMTS = @bitCast(@as(u8, 0)),
    tsw: TMTS = @bitCast(@as(u8, 0)),

    cgwsel: CGWSEL = @bitCast(@as(u8, 0)),
    cgadsub: CGADSUB = @bitCast(@as(u8, 0)),
    coldata: CGDATA = @bitCast(@as(u16, 0)),

    stat78: STAT78 = @bitCast(@as(u8, 1)),
    wrio: u8 = 0xff,
    ophct: u16 = 0,
    opvct: u16 = 0,
    ophct_l: bool = true,
    opvct_l: bool = true,

    rdnmi: RDNMI = @bitCast(@as(u8, 2)),
    hvbjoy: HVBJOY = @bitCast(@as(u8, 0)),
    nmitimen: NMITIMEN = @bitCast(@as(u8, 0)),
    irq_requested: bool = false,
    htime: u9 = 0x1ff,
    vtime: u9 = 0x1ff,

    scanline: u16 = 0,
    dot: u16 = 0,
    cycle_counter: u32 = 0,
    extra_cpu_cycles: u32 = 0,
    true_hires: bool = false,

    openbus: *u8,
    input: *Input,
    dma: *DMA,
    render_width: *f32,
    render_height: *f32,

    pub fn init(allocator: std.mem.Allocator, openbus: *u8, input: *Input, dma: *DMA, render_width: *f32, render_height: *f32) !*PPU {
        const instance = try allocator.create(PPU);
        instance.* = .{
            .allocator = allocator,
            .openbus = openbus,
            .input = input,
            .dma = dma,
            .render_width = render_width,
            .render_height = render_height,
            .framebuf = try allocator.alloc(u32, 512 * 478),
            .output = try allocator.alloc(u32, 512 * 478),
            .vram = try allocator.alloc(u16, 0x8000),
            .cgram = try allocator.alloc(u16, 0x100),
            .oam = try allocator.alloc(u8, 0x220),
        };
        @memset(instance.framebuf, 0);
        @memset(instance.output, 0);
        @memset(instance.vram, 0);
        @memset(instance.cgram, 0);
        @memset(instance.oam, 0);
        return instance;
    }

    pub fn deinit(self: *PPU) void {
        self.allocator.free(self.framebuf);
        self.allocator.free(self.output);
        self.allocator.free(self.vram);
        self.allocator.free(self.cgram);
        self.allocator.free(self.oam);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn prefetch(self: *PPU) void {
        self.vmdata = self.vram[self.remap(self.vmadd) % self.vram.len];
    }

    fn remap(self: *PPU, addr: u16) u16 {
        var v = addr;
        switch (self.vmain.remapping) {
            .none => {},
            .b8 => {
                const r = std.math.rotl(u8, @as(u8, @truncate(v)), 3);
                v &= 0xff00;
                v |= r;
            },
            .b9 => {
                var r: u12 = @as(u12, @truncate(v)) << 3;
                r |= r >> 9;
                v &= 0xfe00;
                v |= @as(u9, @truncate(r));
            },
            .b10 => {
                var r: u13 = @as(u13, @truncate(v)) << 3;
                r |= r >> 10;
                v &= 0xfc00;
                v |= @as(u10, @truncate(r));
            },
        }
        return v;
    }

    pub fn read(ctx: *anyopaque, address: u24) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return switch (address) {
            @intFromEnum(IO.RDOAM) => blk: {
                const v = self.oam[self.oamadd % self.oam.len];
                self.oamadd +%= 1;
                break :blk v;
            },

            @intFromEnum(IO.RDVMDATAL) => blk: {
                const v = self.vmdata;
                self.prefetch();
                if (self.vmain.address_increment_mode == .low) {
                    switch (self.vmain.increment_size) {
                        .w1 => self.vmadd +%= 1,
                        .w32 => self.vmadd +%= 32,
                        .w128 => self.vmadd +%= 128,
                        .w128_2 => self.vmadd +%= 128,
                    }
                }
                break :blk @intCast(v & 0xff);
            },

            @intFromEnum(IO.RDVMDATAH) => blk: {
                const v = self.vmdata;
                self.prefetch();
                if (self.vmain.address_increment_mode == .high) {
                    switch (self.vmain.increment_size) {
                        .w1 => self.vmadd +%= 1,
                        .w32 => self.vmadd +%= 32,
                        .w128 => self.vmadd +%= 128,
                        .w128_2 => self.vmadd +%= 128,
                    }
                }
                break :blk @intCast(v >> 8);
            },

            @intFromEnum(IO.RDCGRAM) => blk: {
                const cg = self.cgram[self.cgadd];
                var v: u8 = 0;
                if (self.cgdata_l) {
                    v = @intCast(cg & 0xff);
                } else {
                    self.cgadd +%= 1;
                    v = @intCast(cg >> 8);
                }
                self.cgdata_l = !self.cgdata_l;
                break :blk v;
            },

            @intFromEnum(IO.TIMEUP) => blk: {
                const v: u8 = @as(u8, if (self.irq_requested) 0x80 else 0);
                self.irq_requested = false;
                break :blk v;
            },

            @intFromEnum(IO.RDNMI) => blk: {
                const v: u8 = @bitCast(self.rdnmi);
                self.rdnmi.vblank = false;
                self.rdnmi.openbus = @intCast((self.openbus.* >> 4) & 0x7);
                break :blk v;
            },

            @intFromEnum(IO.SLHV) => blk: {
                if ((self.wrio & 0x80) > 0) {
                    self.ophct = self.dot;
                    self.opvct = self.scanline;
                    self.stat78.counter_latch = true;
                }
                break :blk self.openbus.*;
            },

            @intFromEnum(IO.OPHCT) => blk: {
                const v = if (self.ophct_l) @as(u8, @intCast(self.ophct & 0xff)) else @as(u8, @intCast(self.ophct >> 8));
                self.ophct_l = !self.ophct_l;
                break :blk v;
            },

            @intFromEnum(IO.OPVCT) => blk: {
                const v = if (self.opvct_l) @as(u8, @intCast(self.opvct & 0xff)) else @as(u8, @intCast(self.opvct >> 8));
                self.opvct_l = !self.opvct_l;
                break :blk v;
            },

            @intFromEnum(IO.STAT77) => blk: {
                self.stat77.ppu1_openbus = @intCast((self.openbus.* >> 4) & 1);
                break :blk @as(u8, @bitCast(self.stat77));
            },

            @intFromEnum(IO.STAT78) => blk: {
                self.stat78.ppu2_openbus = @intCast((self.openbus.* >> 5) & 1);
                self.ophct_l = true;
                self.opvct_l = true;
                self.stat78.counter_latch = false;
                break :blk @as(u8, @bitCast(self.stat78));
            },

            @intFromEnum(IO.HVBJOY) => blk: {
                self.hvbjoy.openbus = @intCast((self.openbus.* >> 1) & 0x1f);
                break :blk @as(u8, @bitCast(self.hvbjoy));
            },

            @intFromEnum(IO.MPYL) => @intCast(self.mpy & 0xff),
            @intFromEnum(IO.MPYM) => @intCast((self.mpy >> 8) & 0xff),
            @intFromEnum(IO.MPYH) => @intCast((self.mpy >> 16) & 0xff),

            else => self.openbus.*,
        };
    }

    pub fn write(ctx: *anyopaque, address: u24, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        switch (address) {
            @intFromEnum(IO.NMITIMEN) => {
                self.nmitimen = @bitCast(value);
                if (self.nmitimen.hv_timer_irq == .off) {
                    self.irq_requested = false;
                }
            },

            @intFromEnum(IO.WRIO) => {
                if ((value & 0x80) == 0 and (self.wrio & 0x80) > 0) {
                    self.ophct = self.dot;
                    self.opvct = self.scanline;
                    self.stat78.counter_latch = true;
                }
                self.wrio = value;
            },

            @intFromEnum(IO.HTIMEL) => {
                self.htime &= 0x100;
                self.htime |= value;
            },

            @intFromEnum(IO.HTIMEH) => {
                self.htime &= 0x0ff;
                self.htime |= @as(u9, value & 1) << 8;
            },

            @intFromEnum(IO.VTIMEL) => {
                self.vtime &= 0x100;
                self.vtime |= value;
            },

            @intFromEnum(IO.VTIMEH) => {
                self.vtime &= 0x0ff;
                self.vtime |= @as(u9, value & 1) << 8;
            },

            @intFromEnum(IO.OAMADDL) => {
                self.oamaddl = value;
                self.oamadd &= 0x200;
                self.oamadd |= @as(u9, value) << 1;
            },

            @intFromEnum(IO.OAMADDH) => {
                self.oamaddh.priority_rotation = (value & 0x80) > 0;
                self.oamaddh.address_high_bit = @intCast(value & 1);
                self.oamadd &= 0x1fe;
                self.oamadd |= @as(u10, if ((value & 1) > 0) 0x200 else 0);
            },

            @intFromEnum(IO.OAMDATA) => {
                if ((self.oamadd & 1) == 0) {
                    self.oamdata = value;
                }
                if (self.oamadd < 0x200 and (self.oamadd & 1) == 1) {
                    self.oam[(self.oamadd -% 1) % self.oam.len] = self.oamdata;
                    self.oam[self.oamadd % self.oam.len] = value;
                }
                if (self.oamadd >= 0x200) {
                    self.oam[self.oamadd % self.oam.len] = value;
                }
                self.oamadd +%= 1;
            },

            @intFromEnum(IO.CGADD) => {
                self.cgadd = value;
                self.cgdata_l = true;
            },

            @intFromEnum(IO.CGDATA) => {
                if (self.cgdata_l) {
                    self.cgdata = value;
                } else {
                    self.cgram[self.cgadd] = (@as(u16, value) << 8) | self.cgdata;
                    self.cgadd +%= 1;
                }
                self.cgdata_l = !self.cgdata_l;
            },

            @intFromEnum(IO.VMADDL) => {
                self.vmadd &= 0xff00;
                self.vmadd |= value;
                self.prefetch();
            },

            @intFromEnum(IO.VMADDH) => {
                self.vmadd &= 0x00ff;
                self.vmadd |= @as(u16, value) << 8;
                self.prefetch();
            },

            @intFromEnum(IO.VMDATAL) => {
                if (self.inidisp.forced_blanking or self.hvbjoy.vblank) {
                    const addr = self.remap(self.vmadd) % self.vram.len;
                    var v = self.vram[addr];
                    v &= 0xff00;
                    v |= value;
                    self.vram[addr] = v;
                }
                if (self.vmain.address_increment_mode == .low) {
                    switch (self.vmain.increment_size) {
                        .w1 => self.vmadd +%= 1,
                        .w32 => self.vmadd +%= 32,
                        .w128 => self.vmadd +%= 128,
                        .w128_2 => self.vmadd +%= 128,
                    }
                }
            },

            @intFromEnum(IO.VMDATAH) => {
                if (self.inidisp.forced_blanking or self.hvbjoy.vblank) {
                    const addr = self.remap(self.vmadd) % self.vram.len;
                    var v = self.vram[addr];
                    v &= 0x00ff;
                    v |= @as(u16, value) << 8;
                    self.vram[addr] = v;
                }
                if (self.vmain.address_increment_mode == .high) {
                    switch (self.vmain.increment_size) {
                        .w1 => self.vmadd +%= 1,
                        .w32 => self.vmadd +%= 32,
                        .w128 => self.vmadd +%= 128,
                        .w128_2 => self.vmadd +%= 128,
                    }
                }
            },

            @intFromEnum(IO.BG1HOFS) => {
                self.bg1hofs = (@as(u10, value & 3) << 8) | (self.bgofs_latch & 0xf8) | (self.bghofs_latch & 7);
                self.bgofs_latch = value;
                self.bghofs_latch = value;
                self.m7hofs = (@as(u13, value & 0x1f) << 8) | self.m7_latch;
                self.m7_latch = value;
            },

            @intFromEnum(IO.BG1VOFS) => {
                self.bg1vofs = (@as(u10, value & 3) << 8) | self.bgofs_latch;
                self.bgofs_latch = value;
                self.m7vofs = (@as(u13, value & 0x1f) << 8) | self.m7_latch;
                self.m7_latch = value;
            },

            @intFromEnum(IO.BG2HOFS) => {
                self.bg2hofs = (@as(u10, value & 3) << 8) | (self.bgofs_latch & 0xf8) | (self.bghofs_latch & 7);
                self.bgofs_latch = value;
                self.bghofs_latch = value;
            },

            @intFromEnum(IO.BG2VOFS) => {
                self.bg2vofs = (@as(u10, value & 3) << 8) | self.bgofs_latch;
                self.bgofs_latch = value;
            },

            @intFromEnum(IO.BG3HOFS) => {
                self.bg3hofs = (@as(u10, value & 3) << 8) | (self.bgofs_latch & 0xf8) | (self.bghofs_latch & 7);
                self.bgofs_latch = value;
                self.bghofs_latch = value;
            },

            @intFromEnum(IO.BG3VOFS) => {
                self.bg3vofs = (@as(u10, value & 3) << 8) | self.bgofs_latch;
                self.bgofs_latch = value;
            },

            @intFromEnum(IO.BG4HOFS) => {
                self.bg4hofs = (@as(u10, value & 3) << 8) | (self.bgofs_latch & 0xf8) | (self.bghofs_latch & 7);
                self.bgofs_latch = value;
                self.bghofs_latch = value;
            },

            @intFromEnum(IO.BG4VOFS) => {
                self.bg4vofs = (@as(u10, value & 3) << 8) | self.bgofs_latch;
                self.bgofs_latch = value;
            },

            @intFromEnum(IO.M7A) => {
                self.m7a = (@as(u16, value) << 8) | self.m7_latch;
                self.m7_latch = value;
                self.mpy = @truncate(@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(self.m7a))) * @as(i32, @as(i8, @bitCast(@as(u8, @intCast(self.m7b & 0xff))))))));
            },

            @intFromEnum(IO.M7B) => {
                self.m7b = (@as(u16, value) << 8) | self.m7_latch;
                self.m7_latch = value;
                self.mpy = @truncate(@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(self.m7a))) * @as(i32, @as(i8, @bitCast(value))))));
            },

            @intFromEnum(IO.M7C) => {
                self.m7c = (@as(u16, value) << 8) | self.m7_latch;
                self.m7_latch = value;
            },

            @intFromEnum(IO.M7D) => {
                self.m7d = (@as(u16, value) << 8) | self.m7_latch;
                self.m7_latch = value;
            },

            @intFromEnum(IO.M7X) => {
                self.m7x = (@as(u13, value & 0x1f) << 8) | self.m7_latch;
                self.m7_latch = value;
            },

            @intFromEnum(IO.M7Y) => {
                self.m7y = (@as(u13, value & 0x1f) << 8) | self.m7_latch;
                self.m7_latch = value;
            },

            @intFromEnum(IO.BGMODE) => {
                const old_width = self.render_width.*;

                self.bgmode = @bitCast(value);
                if (self.bgmode.bg_mode == 5 or self.bgmode.bg_mode == 6) {
                    self.true_hires = true;
                    self.render_width.* = 512;
                } else {
                    self.true_hires = false;
                    self.render_width.* = 256;
                }

                if (old_width != self.render_width.*) {
                    @memset(self.framebuf, 0);
                    @memset(self.output, 0);
                }
            },

            @intFromEnum(IO.INIDISP) => {
                const prev_forced = self.inidisp.forced_blanking;
                self.inidisp = @bitCast(value);
                if (prev_forced and !self.inidisp.forced_blanking) {
                    self.oamadd = 0;
                    self.oamadd |= @as(u9, self.oamaddl) << 1;
                    self.oamadd |= @as(u10, if (self.oamaddh.address_high_bit > 0) 0x200 else 0);
                }
            },

            @intFromEnum(IO.VMAIN) => self.vmain = @bitCast(value),
            @intFromEnum(IO.OBJSEL) => self.objsel = @bitCast(value),
            @intFromEnum(IO.MOSAIC) => self.mosaic = @bitCast(value),
            @intFromEnum(IO.BG1SC) => self.bg1sc = @bitCast(value),
            @intFromEnum(IO.BG2SC) => self.bg2sc = @bitCast(value),
            @intFromEnum(IO.BG3SC) => self.bg3sc = @bitCast(value),
            @intFromEnum(IO.BG4SC) => self.bg4sc = @bitCast(value),
            @intFromEnum(IO.BG12NBA) => self.bg12nba = @bitCast(value),
            @intFromEnum(IO.BG34NBA) => self.bg34nba = @bitCast(value),

            @intFromEnum(IO.W12SEL) => self.w12sel = @bitCast(value),
            @intFromEnum(IO.W34SEL) => self.w34sel = @bitCast(value),
            @intFromEnum(IO.WOBJSEL) => self.wobjsel = @bitCast(value),
            @intFromEnum(IO.WBGLOG) => self.wbglog = @bitCast(value),
            @intFromEnum(IO.WOBJLOG) => self.wobjlog = @bitCast(value),
            @intFromEnum(IO.WH0) => self.wh0 = value,
            @intFromEnum(IO.WH1) => self.wh1 = value,
            @intFromEnum(IO.WH2) => self.wh2 = value,
            @intFromEnum(IO.WH3) => self.wh3 = value,

            @intFromEnum(IO.TM) => self.tm = @bitCast(value),
            @intFromEnum(IO.TS) => self.ts = @bitCast(value),
            @intFromEnum(IO.TMW) => self.tmw = @bitCast(value),
            @intFromEnum(IO.TSW) => self.tsw = @bitCast(value),

            @intFromEnum(IO.CGWSEL) => self.cgwsel = @bitCast(value),
            @intFromEnum(IO.CGADSUB) => self.cgadsub = @bitCast(value),
            @intFromEnum(IO.M7SEL) => self.m7sel = @bitCast(value),

            @intFromEnum(IO.COLDATA) => {
                const data: COLDATA = @bitCast(value);
                if (data.red) self.coldata.red = data.color;
                if (data.green) self.coldata.green = data.color;
                if (data.blue) self.coldata.blue = data.color;
            },

            @intFromEnum(IO.SETINI) => {
                const old_height = self.render_height.*;
                self.setini = @bitCast(value);
                const interlacing: f32 = if (self.setini.screen_interlacing) 2.0 else 1.0;
                self.render_height.* = @as(f32, if (self.setini.overscan or self.stat78.mode == .pal) 239.0 else 224.0) * interlacing;
                if (old_height != self.render_height.*) {
                    @memset(self.framebuf, 0);
                    @memset(self.output, 0);
                }
            },

            else => {},
        }
    }

    // returns all OBJ colors of the entire scanline, their priorities, and if it was palette 0-3 (opaque for the color math)
    fn fetchOBJs(self: *PPU, ly: usize) std.meta.Tuple(&.{ [256]?CGDATA, [256]u2, [256]bool }) {
        var pattern: [256]?CGDATA = [_]?CGDATA{null} ** 256;
        var priorities: [256]u2 = [_]u2{0} ** 256;
        var opaques: [256]bool = [_]bool{false} ** 256;

        var i: usize = @as(usize, if (self.oamaddh.priority_rotation) self.oamaddl >> 1 else 0);
        var overflow_cnt: u8 = 0;
        var sprite_cnt: u8 = 0;

        const sizes: [4]u16 = switch (self.objsel.obj_sprite_size) {
            .s8x8_16x16 => .{ 8, 8, 16, 16 },
            .s8x8_32x32 => .{ 8, 8, 32, 32 },
            .s8x8_64x64 => .{ 8, 8, 64, 64 },
            .s16x16_32x32 => .{ 16, 16, 32, 32 },
            .s16x16_64x64 => .{ 16, 16, 64, 64 },
            .s32x32_64x64 => .{ 32, 32, 64, 64 },
            .s16x32_32x64 => .{ 16, 32, 32, 64 },
            .s16x32_32x32 => .{ 16, 32, 32, 32 },
        };

        var sprites = std.ArrayList(OAMEntry).init(std.heap.c_allocator);
        defer sprites.deinit();

        for (0..128) |_| {
            const oam: OAM = @bitCast((@as(u32, self.oam[(i * 4) + 3]) << 24) | (@as(u32, self.oam[(i * 4) + 2]) << 16) | (@as(u32, self.oam[(i * 4) + 1]) << 8) | (@as(u32, self.oam[i * 4])));
            const oam_aux: OAMAux = @bitCast(self.oam[0x200 + (i / 4)]);

            const high_pos_x: u8 = switch (i % 4) {
                0 => oam_aux.posx_0,
                1 => oam_aux.posx_1,
                2 => oam_aux.posx_2,
                3 => oam_aux.posx_3,
                else => 0,
            };

            const select_size: u1 = switch (i % 4) {
                0 => oam_aux.size_0,
                1 => oam_aux.size_1,
                2 => oam_aux.size_2,
                3 => oam_aux.size_3,
                else => 0,
            };

            const width = if (select_size == 0) sizes[0] else sizes[2];
            var height = if (select_size == 0) sizes[1] else sizes[3];
            var max_offset_y = height - 1;

            const pos_x: i9 = @bitCast(@as(u9, @truncate((@as(u16, high_pos_x) << 8) | oam.pos_x)));
            var pos_y: u16 = oam.pos_y;
            var offset_y: usize = 0;
            if (pos_y > (256 - height)) {
                if (ly < height - (256 - pos_y)) {
                    offset_y = ly + (256 - pos_y);
                    height -= @intCast(256 - pos_y);
                    pos_y = 0;
                }
            } else if (ly > pos_y) {
                if (ly < (pos_y + height)) {
                    offset_y = ly - pos_y;
                }
            }
            if (self.setini.obj_interlacing) {
                offset_y = offset_y * 2 + self.stat78.interlace_field;
                max_offset_y = max_offset_y * 2 + 1;
                height /= 2;
            }
            if (oam.flip_v) {
                offset_y = max_offset_y - offset_y;
            }

            if (ly >= pos_y and ly < (pos_y + height)) {
                if ((pos_x >= 0 and pos_x <= 255) or (@as(i32, pos_x) + @as(i32, width)) >= 0) {
                    sprite_cnt += 1;
                    sprites.append(.{
                        .oam = oam,
                        .width = width,
                        .height = height,
                        .pos_x = pos_x,
                        .offset_y = offset_y,
                    }) catch unreachable;
                } else if (high_pos_x == 1 and oam.pos_x == 0) {
                    // hardware bug
                    sprite_cnt += 1;
                    overflow_cnt += 1;
                }
            }

            if (sprite_cnt >= 33) {
                self.stat77.range_over = true;
                break;
            }

            i += 1;
            if (i == 128) i = 0;
        }

        var pos: usize = sprites.items.len;
        while (pos > 0) {
            pos -= 1;
            const sprite = sprites.items[pos];
            var sprite_pattern: [64]?CGDATA = [_]?CGDATA{null} ** 64;
            var addr: usize = (@as(usize, self.objsel.name_base_address) << 13) + (if (sprite.oam.name_select) ((@as(usize, self.objsel.name_secondary_select) + 1) << 12) else 0);
            var tile_idx: u8 = sprite.oam.tile_index;
            tile_idx +%= @intCast((sprite.offset_y / 8 * 0x10) & 0xff);
            addr += @as(usize, tile_idx) << 4;
            addr += sprite.offset_y % 8;

            for (0..sprite.width / 8) |offset| {
                overflow_cnt += 1;
                if (overflow_cnt >= 35) {
                    self.stat77.time_over = true;
                    break;
                }

                var shift: u3 = 0;
                var color: [8]u8 = [_]u8{0} ** 8;
                for (0..2) |_| {
                    const chr = self.vram[addr % self.vram.len];
                    addr += 8;
                    const plane0: u8 = @intCast(chr & 0xff);
                    const plane1: u8 = @intCast(chr >> 8);
                    for (0..8) |j| {
                        var color_idx = color[j];
                        const b: u3 = 7 - @as(u3, @intCast(j));
                        color_idx |= ((plane0 >> b) & 1) << shift;
                        color_idx |= ((plane1 >> b) & 1) << (shift + 1);
                        color[j] = color_idx;
                    }
                    shift +|= 2;
                }

                for (0..8) |j| {
                    if (color[j] != 0) {
                        sprite_pattern[(offset * 8) + j] = @bitCast(self.cgram[128 + @as(usize, sprite.oam.palette) * 16 + color[j]]);
                    }
                }

                tile_idx +%= 1;
                addr &= 0xfff007;
                addr |= @as(usize, tile_idx) << 4;
            }

            if (sprite.oam.flip_h) {
                std.mem.reverse(?CGDATA, sprite_pattern[0..sprite.width]);
            }

            for (0..sprite.width) |j| {
                if (sprite_pattern[j]) |p| {
                    const pos_x: i16 = @as(i16, sprite.pos_x) + @as(u8, @truncate(j));
                    if (pos_x >= 0 and pos_x <= 255) {
                        const x: usize = @intCast(pos_x);
                        pattern[x] = p;
                        priorities[x] = sprite.oam.priority;
                        opaques[x] = sprite.oam.palette < 4;
                    }
                }
            }
        }

        return .{ pattern, priorities, opaques };
    }

    fn fetchMode7Tiles(self: *PPU, ly: usize) [256]?u8 {
        var pattern: [256]?u8 = [_]?u8{null} ** 256;

        const ma: i32 = @as(i16, @bitCast(self.m7a));
        const mb: i32 = @as(i16, @bitCast(self.m7b));
        const mc: i32 = @as(i16, @bitCast(self.m7c));
        const md: i32 = @as(i16, @bitCast(self.m7d));
        const mx: i32 = @as(i13, @bitCast(self.m7x));
        const my: i32 = @as(i13, @bitCast(self.m7y));
        const mh: i32 = @as(i13, @bitCast(self.m7hofs));
        const mv: i32 = @as(i13, @bitCast(self.m7vofs));
        var sy: i32 = @intCast(ly);
        var sx: i32 = 0;

        if (self.m7sel.flip_h) sx ^= 0xff;
        if (self.m7sel.flip_v) sy ^= 0xff;
        var tx: i32 = (mh - mx) & ~@as(i32, 0x1c00);
        if (tx < 0) tx |= 0x1c00;
        var ty: i32 = (mv - my) & ~@as(i32, 0x1c00);
        if (ty < 0) ty |= 0x1c00;
        var x: i32 = ((ma * tx) & ~@as(i32, 0x3f)) + ((mb * ty) & ~@as(i32, 0x3f)) + mx * 0x100;
        var y: i32 = ((mc * tx) & ~@as(i32, 0x3f)) + ((md * ty) & ~@as(i32, 0x3f)) + my * 0x100;
        x += ((mb * sy) & ~@as(i32, 0x3f)) + (ma * sx);
        y += ((md * sy) & ~@as(i32, 0x3f)) + (mc * sx);

        for (0..256) |i| {
            const addr_x: Mode7Addr = @bitCast(x);
            const addr_y: Mode7Addr = @bitCast(y);
            const entry: u8 = @intCast(self.vram[(@as(usize, addr_y.map_index) * 128 + @as(usize, addr_x.map_index)) % 0x4000] & 0xff);
            const idx = @as(usize, entry) * 64 + @as(usize, addr_y.pixel_index) * 8 + @as(usize, addr_x.pixel_index);
            const color: u8 = @intCast(self.vram[idx % 0x4000] >> 8);
            if (color != 0) {
                if (!self.m7sel.tilemap_norepeat or (addr_x.zero == 0 and addr_y.zero == 0)) {
                    pattern[i] = color;
                } else if (self.m7sel.fill) {
                    pattern[i] = @intCast(self.vram[0] >> 8);
                }
            }

            if (self.m7sel.flip_h) x -= ma else x += ma;
            if (self.m7sel.flip_h) y -= mc else y += mc;
        }

        return pattern;
    }

    fn fetchBG1Tile(self: *PPU, lx: usize, ly: usize) std.meta.Tuple(&.{ [8]?CGDATA, BGMapAttr }) {
        const large_x = self.bgmode.bg1_char_size == .s16x16 or self.true_hires;
        const large_y = self.bgmode.bg1_char_size == .s16x16;
        const size_x: usize = if (large_x) 16 else 8;
        const size_y: usize = if (large_y) 16 else 8;

        var hofs: usize = self.bg1hofs;
        var vofs: usize = self.bg1vofs;

        if (self.bgmode.bg_mode == 2 or self.bgmode.bg_mode == 4 or self.bgmode.bg_mode == 6) {
            if (lx > 0) {
                const r = self.fetchOffsetPerTile((lx / 8) - @as(usize, if (self.bg1hofs == 0) 1 else 0), 0);
                if (r.@"1") |v| vofs = v;
                if (r.@"0") |h| hofs = (hofs & 7) | h;
            }
        }

        var y = ly;

        const mosaic = struct {
            var color: ?CGDATA = null;
            var size: usize = 0;
            var x_offset: usize = 0;
            var y_offset: usize = 0;
        };

        if (self.mosaic.bg1_enable) {
            if (mosaic.y_offset == mosaic.size) {
                mosaic.size = @as(usize, self.mosaic.size) + 1;
                mosaic.y_offset = 0;
            }
            mosaic.y_offset += 1;
            y = y / mosaic.size * mosaic.size;
        } else {
            mosaic.size = 0;
            mosaic.y_offset = 0;
        }

        var x = lx + hofs;

        if (self.true_hires) {
            x *= 2;
            if (self.setini.screen_interlacing) {
                y = y * 2 + self.stat78.interlace_field;
            }
        }

        y += vofs;

        const tx: usize = x / size_x;
        const ty: usize = y / size_y;

        var attr: BGMapAttr = undefined;
        {
            var mapaddr = (@as(usize, self.bg1sc.tilemap_address) << 10) | ((ty & 0x1f) << 5) | (tx & 0x1f);
            if (self.bg1sc.large_horizontal) mapaddr += (tx & 0x20) << 5;
            if (self.bg1sc.large_vertical) mapaddr += (ty & 0x20) << @as(u3, if (self.bg1sc.large_horizontal) 6 else 5);
            attr = @bitCast(self.vram[mapaddr % self.vram.len]);
        }

        const bpp = @as(usize, switch (self.bgmode.bg_mode) {
            0 => 2,
            1 => 4,
            2 => 4,
            3 => 8,
            4 => 8,
            5 => 4,
            6 => 4,
            7 => 0,
        }) >> 1; // each index is a 16-bit word

        var addr: usize = @as(usize, self.bg12nba.bg1_chr_base_address) << 12;
        addr += @as(usize, attr.tile_index) * 8 * bpp;

        if (attr.flip_h) {
            if (large_x and (x % 16) < 8) addr += 8 * bpp;
        } else {
            if (large_x and (x % 16) >= 8) addr += 8 * bpp;
        }

        if (attr.flip_v) {
            if (large_y and (y % 16) < 8) addr += 0x80 * bpp;
            addr += 7 - (y % 8);
        } else {
            if (large_y and (y % 16) >= 8) addr += 0x80 * bpp;
            addr += y % 8;
        }

        var pattern: [8]?CGDATA = [_]?CGDATA{null} ** 8;
        var shift: u3 = 0;
        var color: [8]u8 = [_]u8{0} ** 8;
        for (0..bpp) |_| {
            const chr = self.vram[addr % self.vram.len];
            addr += 8;
            const plane0: u8 = @intCast(chr & 0xff);
            const plane1: u8 = @intCast(chr >> 8);
            for (0..8) |i| {
                var color_idx = color[i];
                const b: u3 = 7 - @as(u3, @intCast(i));
                color_idx |= ((plane0 >> b) & 1) << shift;
                color_idx |= ((plane1 >> b) & 1) << (shift + 1);
                color[i] = color_idx;
            }
            shift +|= 2;
        }

        for (0..8) |i| {
            if (color[i] != 0) {
                switch (self.bgmode.bg_mode) {
                    0 => pattern[i] = @bitCast(self.cgram[@as(usize, attr.palette) * 4 + color[i]]),
                    1 => pattern[i] = @bitCast(self.cgram[@as(usize, attr.palette) * 16 + color[i]]),
                    2 => pattern[i] = @bitCast(self.cgram[@as(usize, attr.palette) * 16 + color[i]]),
                    3 => pattern[i] = if (self.cgwsel.direct_color_mode) directColor(attr.palette, color[i]) else @bitCast(self.cgram[color[i]]),
                    4 => pattern[i] = if (self.cgwsel.direct_color_mode) directColor(attr.palette, color[i]) else @bitCast(self.cgram[color[i]]),
                    5 => pattern[i] = @bitCast(self.cgram[@as(usize, attr.palette) * 16 + color[i]]),
                    6 => pattern[i] = @bitCast(self.cgram[@as(usize, attr.palette) * 16 + color[i]]),
                    7 => {},
                }
            }
        }

        if (attr.flip_h) {
            std.mem.reverse(?CGDATA, &pattern);
        }

        if (mosaic.size > 0) {
            if (lx == 0) mosaic.x_offset = 0;
            for (0..8) |i| {
                if (mosaic.x_offset == 0) {
                    mosaic.color = pattern[i];
                } else {
                    pattern[i] = mosaic.color;
                }

                mosaic.x_offset += 1;
                if (mosaic.x_offset == mosaic.size) {
                    mosaic.x_offset = 0;
                }
            }
        }

        return .{ pattern, attr };
    }

    fn fetchBG2Tile(self: *PPU, lx: usize, ly: usize) std.meta.Tuple(&.{ [8]?CGDATA, BGMapAttr }) {
        const large_x = self.bgmode.bg2_char_size == .s16x16 or self.true_hires;
        const large_y = self.bgmode.bg2_char_size == .s16x16;
        const size_x: usize = if (large_x) 16 else 8;
        const size_y: usize = if (large_y) 16 else 8;

        var hofs: usize = self.bg2hofs;
        var vofs: usize = self.bg2vofs;

        if (self.bgmode.bg_mode == 2 or self.bgmode.bg_mode == 4 or self.bgmode.bg_mode == 6) {
            if (lx > 0) {
                const r = self.fetchOffsetPerTile((lx / 8) - @as(usize, if (self.bg2hofs == 0) 1 else 0), 1);
                if (r.@"1") |v| vofs = v;
                if (r.@"0") |h| hofs = (hofs & 7) | h;
            }
        }

        var y = ly;

        const mosaic = struct {
            var color: ?CGDATA = null;
            var size: usize = 0;
            var x_offset: usize = 0;
            var y_offset: usize = 0;
        };

        if (self.mosaic.bg2_enable) {
            if (mosaic.y_offset == mosaic.size) {
                mosaic.size = @as(usize, self.mosaic.size) + 1;
                mosaic.y_offset = 0;
            }
            mosaic.y_offset += 1;
            y = y / mosaic.size * mosaic.size;
        } else {
            mosaic.size = 0;
            mosaic.y_offset = 0;
        }

        var x = lx + hofs;

        if (self.true_hires) {
            x *= 2;
            if (self.setini.screen_interlacing) {
                y = y * 2 + self.stat78.interlace_field;
            }
        }

        y += vofs;

        const tx: usize = x / size_x;
        const ty: usize = y / size_y;

        var attr: BGMapAttr = undefined;
        {
            var mapaddr = (@as(usize, self.bg2sc.tilemap_address) << 10) | ((ty & 0x1f) << 5) | (tx & 0x1f);
            if (self.bg2sc.large_horizontal) mapaddr += (tx & 0x20) << 5;
            if (self.bg2sc.large_vertical) mapaddr += (ty & 0x20) << @as(u3, if (self.bg2sc.large_horizontal) 6 else 5);
            attr = @bitCast(self.vram[mapaddr % self.vram.len]);
        }

        const bpp = @as(usize, switch (self.bgmode.bg_mode) {
            0 => 2,
            1 => 4,
            2 => 4,
            3 => 4,
            4 => 2,
            5 => 2,
            6 => 0,
            7 => 0,
        }) >> 1; // each index is a 16-bit word

        var addr: usize = @as(usize, self.bg12nba.bg2_chr_base_address) << 12;
        addr += @as(usize, attr.tile_index) * 8 * bpp;

        if (attr.flip_h) {
            if (large_x and (x % 16) < 8) addr += 8 * bpp;
        } else {
            if (large_x and (x % 16) >= 8) addr += 8 * bpp;
        }

        if (attr.flip_v) {
            if (large_y and (y % 16) < 8) addr += 0x80 * bpp;
            addr += 7 - (y % 8);
        } else {
            if (large_y and (y % 16) >= 8) addr += 0x80 * bpp;
            addr += y % 8;
        }

        var pattern: [8]?CGDATA = [_]?CGDATA{null} ** 8;
        var shift: u3 = 0;
        var color: [8]u8 = [_]u8{0} ** 8;
        for (0..bpp) |_| {
            const chr = self.vram[addr % self.vram.len];
            addr += 8;
            const plane0: u8 = @intCast(chr & 0xff);
            const plane1: u8 = @intCast(chr >> 8);
            for (0..8) |i| {
                var color_idx = color[i];
                const b: u3 = 7 - @as(u3, @intCast(i));
                color_idx |= ((plane0 >> b) & 1) << shift;
                color_idx |= ((plane1 >> b) & 1) << (shift + 1);
                color[i] = color_idx;
            }
            shift +|= 2;
        }

        for (0..8) |i| {
            if (color[i] != 0) {
                switch (self.bgmode.bg_mode) {
                    0 => pattern[i] = @bitCast(self.cgram[32 + @as(usize, attr.palette) * 4 + color[i]]),
                    1 => pattern[i] = @bitCast(self.cgram[@as(usize, attr.palette) * 16 + color[i]]),
                    2 => pattern[i] = @bitCast(self.cgram[@as(usize, attr.palette) * 16 + color[i]]),
                    3 => pattern[i] = @bitCast(self.cgram[@as(usize, attr.palette) * 16 + color[i]]),
                    4 => pattern[i] = @bitCast(self.cgram[@as(usize, attr.palette) * 4 + color[i]]),
                    5 => pattern[i] = @bitCast(self.cgram[@as(usize, attr.palette) * 4 + color[i]]),
                    6 => pattern[i] = null,
                    7 => pattern[i] = null,
                }
            }
        }

        if (attr.flip_h) {
            std.mem.reverse(?CGDATA, &pattern);
        }

        if (mosaic.size > 0) {
            if (lx == 0) mosaic.x_offset = 0;
            for (0..8) |i| {
                if (mosaic.x_offset == 0) {
                    mosaic.color = pattern[i];
                } else {
                    pattern[i] = mosaic.color;
                }

                mosaic.x_offset += 1;
                if (mosaic.x_offset == mosaic.size) {
                    mosaic.x_offset = 0;
                }
            }
        }

        return .{ pattern, attr };
    }

    fn fetchBG3Tile(self: *PPU, lx: usize, ly: usize) std.meta.Tuple(&.{ [8]?CGDATA, BGMapAttr }) {
        const large_x = self.bgmode.bg3_char_size == .s16x16;
        const large_y = self.bgmode.bg3_char_size == .s16x16;
        const size_x: usize = if (large_x) 16 else 8;
        const size_y: usize = if (large_y) 16 else 8;

        var y = ly;

        const mosaic = struct {
            var color: ?CGDATA = null;
            var size: usize = 0;
            var x_offset: usize = 0;
            var y_offset: usize = 0;
        };

        if (self.mosaic.bg3_enable) {
            if (mosaic.y_offset == mosaic.size) {
                mosaic.size = @as(usize, self.mosaic.size) + 1;
                mosaic.y_offset = 0;
            }
            mosaic.y_offset += 1;
            y = y / mosaic.size * mosaic.size;
        } else {
            mosaic.size = 0;
            mosaic.y_offset = 0;
        }

        const x = lx + self.bg3hofs;
        y += self.bg3vofs;

        const tx: usize = x / size_x;
        const ty: usize = y / size_y;

        var attr: BGMapAttr = undefined;
        {
            var mapaddr = (@as(usize, self.bg3sc.tilemap_address) << 10) | ((ty & 0x1f) << 5) | (tx & 0x1f);
            if (self.bg3sc.large_horizontal) mapaddr += (tx & 0x20) << 5;
            if (self.bg3sc.large_vertical) mapaddr += (ty & 0x20) << @as(u3, if (self.bg3sc.large_horizontal) 6 else 5);
            attr = @bitCast(self.vram[mapaddr % self.vram.len]);
        }

        var addr: usize = @as(usize, self.bg34nba.bg3_chr_base_address) << 12;
        addr += @as(usize, attr.tile_index) * 8;

        if (attr.flip_h) {
            if (large_x and (x % 16) < 8) addr += 8;
        } else {
            if (large_x and (x % 16) >= 8) addr += 8;
        }

        if (attr.flip_v) {
            if (large_y and (y % 16) < 8) addr += 0x80;
            addr += 7 - (y % 8);
        } else {
            if (large_y and (y % 16) >= 8) addr += 0x80;
            addr += y % 8;
        }

        var pattern: [8]?CGDATA = [_]?CGDATA{null} ** 8;
        var color: [8]u8 = [_]u8{0} ** 8;
        const chr = self.vram[addr % self.vram.len];
        const plane0: u8 = @intCast(chr & 0xff);
        const plane1: u8 = @intCast(chr >> 8);
        for (0..8) |i| {
            var color_idx = color[i];
            color_idx <<= 2;
            const b: u3 = 7 - @as(u3, @intCast(i));
            color_idx |= (plane0 >> b) & 1;
            color_idx |= ((plane1 >> b) & 1) << 1;
            color[i] = color_idx;
        }

        for (0..8) |i| {
            if (color[i] != 0) {
                switch (self.bgmode.bg_mode) {
                    0 => pattern[i] = @bitCast(self.cgram[64 + @as(usize, attr.palette) * 4 + color[i]]),
                    1 => pattern[i] = @bitCast(self.cgram[@as(usize, attr.palette) * 4 + color[i]]),
                    else => {},
                }
            }
        }

        if (attr.flip_h) {
            std.mem.reverse(?CGDATA, &pattern);
        }

        if (mosaic.size > 0) {
            if (lx == 0) mosaic.x_offset = 0;
            for (0..8) |i| {
                if (mosaic.x_offset == 0) {
                    mosaic.color = pattern[i];
                } else {
                    pattern[i] = mosaic.color;
                }

                mosaic.x_offset += 1;
                if (mosaic.x_offset == mosaic.size) {
                    mosaic.x_offset = 0;
                }
            }
        }

        return .{ pattern, attr };
    }

    fn fetchBG4Tile(self: *PPU, lx: usize, ly: usize) std.meta.Tuple(&.{ [8]?CGDATA, BGMapAttr }) {
        const large_x = self.bgmode.bg4_char_size == .s16x16;
        const large_y = self.bgmode.bg4_char_size == .s16x16;
        const size_x: usize = if (large_x) 16 else 8;
        const size_y: usize = if (large_y) 16 else 8;

        var y = ly;

        const mosaic = struct {
            var color: ?CGDATA = null;
            var size: usize = 0;
            var x_offset: usize = 0;
            var y_offset: usize = 0;
        };

        if (self.mosaic.bg4_enable) {
            if (mosaic.y_offset == mosaic.size) {
                mosaic.size = @as(usize, self.mosaic.size) + 1;
                mosaic.y_offset = 0;
            }
            mosaic.y_offset += 1;
            y = y / mosaic.size * mosaic.size;
        } else {
            mosaic.size = 0;
            mosaic.y_offset = 0;
        }

        const x = lx + self.bg4hofs;
        y += self.bg4vofs;

        const tx: usize = x / size_x;
        const ty: usize = y / size_y;

        var attr: BGMapAttr = undefined;
        {
            var mapaddr = (@as(usize, self.bg4sc.tilemap_address) << 10) | ((ty & 0x1f) << 5) | (tx & 0x1f);
            if (self.bg4sc.large_horizontal) mapaddr += (tx & 0x20) << 5;
            if (self.bg4sc.large_vertical) mapaddr += (ty & 0x20) << @as(u3, if (self.bg4sc.large_horizontal) 6 else 5);
            attr = @bitCast(self.vram[mapaddr % self.vram.len]);
        }

        var addr: usize = @as(usize, self.bg34nba.bg4_chr_base_address) << 12;
        addr += @as(usize, attr.tile_index) * 8;

        if (attr.flip_h) {
            if (large_x and (x % 16) < 8) addr += 8;
        } else {
            if (large_x and (x % 16) >= 8) addr += 8;
        }

        if (attr.flip_v) {
            if (large_y and (y % 16) < 8) addr += 0x80;
            addr += 7 - (y % 8);
        } else {
            if (large_y and (y % 16) >= 8) addr += 0x80;
            addr += y % 8;
        }

        var pattern: [8]?CGDATA = [_]?CGDATA{null} ** 8;
        var color: [8]u8 = [_]u8{0} ** 8;
        const chr = self.vram[addr % self.vram.len];
        const plane0: u8 = @intCast(chr & 0xff);
        const plane1: u8 = @intCast(chr >> 8);
        for (0..8) |i| {
            var color_idx = color[i];
            color_idx <<= 2;
            const b: u3 = 7 - @as(u3, @intCast(i));
            color_idx |= (plane0 >> b) & 1;
            color_idx |= ((plane1 >> b) & 1) << 1;
            color[i] = color_idx;
        }

        for (0..8) |i| {
            if (color[i] != 0) {
                pattern[i] = @bitCast(self.cgram[96 + @as(usize, attr.palette) * 4 + color[i]]);
            }
        }

        if (attr.flip_h) {
            std.mem.reverse(?CGDATA, &pattern);
        }

        if (mosaic.size > 0) {
            if (lx == 0) mosaic.x_offset = 0;
            for (0..8) |i| {
                if (mosaic.x_offset == 0) {
                    mosaic.color = pattern[i];
                } else {
                    pattern[i] = mosaic.color;
                }

                mosaic.x_offset += 1;
                if (mosaic.x_offset == mosaic.size) {
                    mosaic.x_offset = 0;
                }
            }
        }

        return .{ pattern, attr };
    }

    fn fetchOffsetPerTile(self: *PPU, tile: usize, layer: u1) std.meta.Tuple(&.{ ?usize, ?usize }) {
        var addr: usize = tile;
        addr += ((self.bg3vofs / 8) & @as(usize, if (self.bg3sc.large_vertical) 0x3f else 0x1f)) << 5;
        addr += (self.bg3hofs / 8) & @as(usize, if (self.bg3sc.large_horizontal) 0x3f else 0x1f);

        const h: OffsetPerTile = @bitCast(self.vram[((@as(usize, self.bg3sc.tilemap_address) << 10) | addr)]);
        const v: OffsetPerTile = @bitCast(self.vram[((@as(usize, self.bg3sc.tilemap_address) << 10) | ((addr + 0x20) & @as(usize, if (self.bg3sc.large_vertical) 0x7ff else 0x3ff)))]);

        var rh: ?usize = null;
        var rv: ?usize = null;
        if (self.bgmode.bg_mode == 4) {
            if (layer == 0 and h.apply_bg1) {
                if (h.hv == .h) rh = h.scroll_offset & 0x3f8;
                if (h.hv == .v) rv = h.scroll_offset;
            }
            if (layer == 1 and h.apply_bg2) {
                if (h.hv == .h) rh = h.scroll_offset & 0x3f8;
                if (h.hv == .v) rv = h.scroll_offset;
            }
        } else {
            if (layer == 0 and h.apply_bg1) rh = h.scroll_offset & 0x3f8;
            if (layer == 1 and h.apply_bg2) rh = h.scroll_offset & 0x3f8;
            if (layer == 0 and v.apply_bg1) rv = v.scroll_offset;
            if (layer == 1 and v.apply_bg2) rv = v.scroll_offset;
        }
        return .{ rh, rv };
    }

    fn directColor(palette: u3, color: u8) CGDATA {
        const cgdata: CGDATA = .{
            .red = @intCast((((color & 7) << 1) | (palette & 1)) << 1),
            .green = @intCast(((((color >> 3) & 7) << 2) | (palette & 2))),
            .blue = @intCast((((color >> 6) << 3) | (palette & 4))),
        };
        return cgdata;
    }

    fn rgbcolor(self: *PPU, color: CGDATA) u32 {
        var cl = color;
        const brightness = @as(usize, self.inidisp.brightness) + 1;
        cl.red = @intCast((@as(usize, cl.red) * brightness) / 16);
        cl.green = @intCast((@as(usize, cl.green) * brightness) / 16);
        cl.blue = @intCast((@as(usize, cl.blue) * brightness) / 16);
        const r: u32 = (@as(u8, cl.red) << 3) | ((cl.red >> 2) & 7);
        const g: u32 = (@as(u8, cl.green) << 3) | ((cl.green >> 2) & 7);
        const b: u32 = (@as(u8, cl.blue) << 3) | ((cl.blue >> 2) & 7);
        return 0xff000000 | (b << 16) | (g << 8) | r;
    }

    fn colormath(self: *PPU, out_color: ?CGDATA, sub_color: ?CGDATA, transparent_subscreen: bool, color_source: ColorSource, obj_opaque: bool) CGDATA {
        var r: u6 = 0;
        var g: u6 = 0;
        var b: u6 = 0;

        if (out_color) |cl| {
            r = cl.red;
            g = cl.green;
            b = cl.blue;
        } else {
            const cl: CGDATA = @bitCast(self.cgram[0]);
            r = cl.red;
            g = cl.green;
            b = cl.blue;
        }

        const perform = switch (color_source) {
            .bg1 => self.cgadsub.bg1_math,
            .bg2 => self.cgadsub.bg2_math,
            .bg3 => self.cgadsub.bg3_math,
            .bg4 => self.cgadsub.bg4_math,
            .obj => self.cgadsub.obj_math and !obj_opaque,
            .backdrop => self.cgadsub.backdrop_math,
        };

        if (perform and !transparent_subscreen) {
            var divide = self.cgadsub.half_math;
            var r2: u6 = self.coldata.red;
            var g2: u6 = self.coldata.green;
            var b2: u6 = self.coldata.blue;

            if (self.cgwsel.add_subscreen) {
                if (sub_color) |cl| {
                    r2 = cl.red;
                    g2 = cl.green;
                    b2 = cl.blue;
                } else {
                    divide = false;
                }
            }

            if (self.cgadsub.subtract) {
                r -|= r2;
                g -|= g2;
                b -|= b2;
            } else {
                r +|= r2;
                g +|= g2;
                b +|= b2;
            }

            if (divide) {
                r /= 2;
                g /= 2;
                b /= 2;
            }
        }

        return .{
            .red = @intCast(@min(31, r)),
            .green = @intCast(@min(31, g)),
            .blue = @intCast(@min(31, b)),
        };
    }

    fn resolvePriority(
        self: *PPU,
        tmts: TMTS,
        backdrop: ?CGDATA,
        obj_color: ?CGDATA,
        bg1_color: ?CGDATA,
        bg2_color: ?CGDATA,
        bg3_color: ?CGDATA,
        bg4_color: ?CGDATA,
        obj_prior: u2,
        bg1_attr: BGMapAttr,
        bg2_attr: BGMapAttr,
        bg3_attr: BGMapAttr,
        bg4_attr: BGMapAttr,
        source: *ColorSource,
    ) ?CGDATA {
        var out_color = backdrop;
        source.* = .backdrop;

        switch (self.bgmode.bg_mode) {
            0 => {
                if (tmts.bg4 and bg4_color != null) {
                    out_color = bg4_color.?;
                    source.* = .bg4;
                }
                if (tmts.bg3 and bg3_color != null) {
                    out_color = bg3_color.?;
                    source.* = .bg3;
                }
                if (tmts.obj and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg4 and bg4_attr.priority and bg4_color != null) {
                    out_color = bg4_color.?;
                    source.* = .bg4;
                }
                if (tmts.bg3 and bg3_attr.priority and bg3_color != null) {
                    out_color = bg3_color.?;
                    source.* = .bg3;
                }
                if (tmts.obj and obj_prior == 1 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg2 and bg2_color != null) {
                    out_color = bg2_color.?;
                    source.* = .bg2;
                }
                if (tmts.bg1 and bg1_color != null) {
                    out_color = bg1_color.?;
                    source.* = .bg1;
                }
                if (tmts.obj and obj_prior == 2 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg2 and bg2_attr.priority and bg2_color != null) {
                    out_color = bg2_color.?;
                    source.* = .bg2;
                }
                if (tmts.bg1 and bg1_attr.priority and bg1_color != null) {
                    out_color = bg1_color.?;
                    source.* = .bg1;
                }
                if (tmts.obj and obj_prior == 3 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
            },
            1 => {
                if (tmts.bg3 and bg3_color != null) {
                    out_color = bg3_color.?;
                    source.* = .bg3;
                }
                if (tmts.obj and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg3 and !self.bgmode.mode1_bg3_priority and bg3_attr.priority and bg3_color != null) {
                    out_color = bg3_color.?;
                    source.* = .bg3;
                }
                if (tmts.obj and obj_prior == 1 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg2 and bg2_color != null) {
                    out_color = bg2_color.?;
                    source.* = .bg2;
                }
                if (tmts.bg1 and bg1_color != null) {
                    out_color = bg1_color.?;
                    source.* = .bg1;
                }
                if (tmts.obj and obj_prior == 2 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg2 and bg2_attr.priority and bg2_color != null) {
                    out_color = bg2_color.?;
                    source.* = .bg2;
                }
                if (tmts.bg1 and bg1_attr.priority and bg1_color != null) {
                    out_color = bg1_color.?;
                    source.* = .bg1;
                }
                if (tmts.obj and obj_prior == 3 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg3 and self.bgmode.mode1_bg3_priority and bg3_attr.priority and bg3_color != null) {
                    out_color = bg3_color.?;
                    source.* = .bg3;
                }
            },
            2, 3, 4, 5 => {
                if (tmts.bg2 and bg2_color != null) {
                    out_color = bg2_color.?;
                    source.* = .bg2;
                }
                if (tmts.obj and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg1 and bg1_color != null) {
                    out_color = bg1_color.?;
                    source.* = .bg1;
                }
                if (tmts.obj and obj_prior == 1 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg2 and bg2_attr.priority and bg2_color != null) {
                    out_color = bg2_color.?;
                    source.* = .bg2;
                }
                if (tmts.obj and obj_prior == 2 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg1 and bg1_attr.priority and bg1_color != null) {
                    out_color = bg1_color.?;
                    source.* = .bg1;
                }
                if (tmts.obj and obj_prior == 3 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
            },
            6 => {
                if (tmts.obj and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg1 and bg1_color != null) {
                    out_color = bg1_color.?;
                    source.* = .bg1;
                }
                if (tmts.obj and obj_prior == 1 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.obj and obj_prior == 2 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg1 and bg1_attr.priority and bg1_color != null) {
                    out_color = bg1_color.?;
                    source.* = .bg1;
                }
                if (tmts.obj and obj_prior == 3 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
            },
            7 => {
                if (self.setini.extbg and bg2_color != null) {
                    out_color = bg2_color.?;
                    source.* = .bg2;
                }
                if (tmts.obj and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.bg1 and bg1_color != null) {
                    out_color = bg1_color.?;
                    source.* = .bg1;
                }
                if (tmts.obj and obj_prior == 1 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (self.setini.extbg and bg2_color != null and bg2_color.?.extbg_priority) {
                    out_color = bg2_color.?;
                    source.* = .bg2;
                }
                if (tmts.obj and obj_prior == 2 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
                if (tmts.obj and obj_prior == 3 and obj_color != null) {
                    out_color = obj_color.?;
                    source.* = .obj;
                }
            },
        }

        return out_color;
    }

    fn draw(self: *PPU) !void {
        const lx: usize = self.dot - 22;
        const ly: usize = self.scanline;
        var color_source: ColorSource = .backdrop;
        var subcolor_source: ColorSource = .backdrop;
        var out_color: ?CGDATA = null;
        var sub_color: ?CGDATA = null;
        var obj_color: ?CGDATA = null;
        var bg1_color: ?CGDATA = null;
        var bg2_color: ?CGDATA = null;
        var bg3_color: ?CGDATA = null;
        var bg4_color: ?CGDATA = null;
        var obj_subcolor: ?CGDATA = null;
        var bg1_subcolor: ?CGDATA = null;
        var bg2_subcolor: ?CGDATA = null;
        var bg3_subcolor: ?CGDATA = null;
        var bg4_subcolor: ?CGDATA = null;

        var start_pos: usize = 0;
        if (self.setini.screen_interlacing) {
            if (self.stat78.interlace_field == 1) start_pos += 512;
            start_pos += (ly - 1) * 1024;
            if (self.stat78.mode == .pal and !self.setini.overscan) start_pos += 8192;
        } else {
            start_pos += (ly - 1) * 512;
            if (self.stat78.mode == .pal and !self.setini.overscan) start_pos += 4096;
        }

        if (self.inidisp.forced_blanking) {
            const black = self.rgbcolor(.{ .red = 0, .green = 0, .blue = 0 });
            if (self.true_hires) {
                self.framebuf[start_pos + lx * 2] = black;
                self.framebuf[start_pos + lx * 2 + 1] = black;
            } else {
                self.framebuf[start_pos + lx] = black;
            }
            return;
        }

        const patterns = struct {
            var mode7: [256]?u8 = [_]?u8{null} ** 256;
            var obj: [256]?CGDATA = [_]?CGDATA{null} ** 256;
            var bg1: std.fifo.LinearFifo(?CGDATA, .{ .Static = 8 }) = std.fifo.LinearFifo(?CGDATA, .{ .Static = 8 }).init();
            var bg2: std.fifo.LinearFifo(?CGDATA, .{ .Static = 8 }) = std.fifo.LinearFifo(?CGDATA, .{ .Static = 8 }).init();
            var bg3: std.fifo.LinearFifo(?CGDATA, .{ .Static = 8 }) = std.fifo.LinearFifo(?CGDATA, .{ .Static = 8 }).init();
            var bg4: std.fifo.LinearFifo(?CGDATA, .{ .Static = 8 }) = std.fifo.LinearFifo(?CGDATA, .{ .Static = 8 }).init();
        };

        const attributes = struct {
            var obj_priorities: [256]u2 = undefined;
            var obj_opaques: [256]bool = undefined;
            var bg1: BGMapAttr = undefined;
            var bg2: BGMapAttr = undefined;
            var bg3: BGMapAttr = undefined;
            var bg4: BGMapAttr = undefined;
        };

        if (lx == 0) {
            const objs = self.fetchOBJs(ly - 1);
            patterns.obj = objs.@"0";
            attributes.obj_priorities = objs.@"1";
            attributes.obj_opaques = objs.@"2";

            patterns.bg1.discard(patterns.bg1.count);
            patterns.bg2.discard(patterns.bg2.count);
            patterns.bg3.discard(patterns.bg3.count);
            patterns.bg4.discard(patterns.bg4.count);

            if (self.bgmode.bg_mode == 7) {
                patterns.mode7 = self.fetchMode7Tiles(ly);
            }
        }

        if (self.bgmode.bg_mode != 7) {
            if (self.tm.bg1 or self.ts.bg1) {
                bg1_color = patterns.bg1.readItem() orelse blk: {
                    var data = self.fetchBG1Tile(lx, ly);
                    attributes.bg1 = data.@"1";
                    try patterns.bg1.write(&data.@"0");
                    if (lx == 0) {
                        if (self.true_hires) {
                            const offset = self.bg1hofs % 8;
                            if (offset >= 4) {
                                data = self.fetchBG1Tile(lx + 1, ly);
                                attributes.bg1 = data.@"1";
                                patterns.bg1.discard(patterns.bg1.count);
                                try patterns.bg1.write(&data.@"0");
                                for (0..(offset - 4) * 2) |_| _ = patterns.bg1.readItem();
                            } else {
                                for (0..offset * 2) |_| _ = patterns.bg1.readItem();
                            }
                        } else {
                            for (0..(self.bg1hofs % 8)) |_| _ = patterns.bg1.readItem();
                        }
                    }
                    break :blk patterns.bg1.readItem().?;
                };
            }

            if ((self.tm.bg2 or self.ts.bg2) and self.bgmode.bg_mode < 6) {
                bg2_color = patterns.bg2.readItem() orelse blk: {
                    var data = self.fetchBG2Tile(lx, ly);
                    attributes.bg2 = data.@"1";
                    try patterns.bg2.write(&data.@"0");
                    if (lx == 0) {
                        if (self.true_hires) {
                            const offset = self.bg2hofs % 8;
                            if (offset >= 4) {
                                data = self.fetchBG2Tile(lx + 1, ly);
                                attributes.bg2 = data.@"1";
                                patterns.bg2.discard(patterns.bg2.count);
                                try patterns.bg2.write(&data.@"0");
                                for (0..(offset - 4) * 2) |_| _ = patterns.bg2.readItem();
                            } else {
                                for (0..offset * 2) |_| _ = patterns.bg2.readItem();
                            }
                        } else {
                            for (0..(self.bg2hofs % 8)) |_| _ = patterns.bg2.readItem();
                        }
                    }
                    break :blk patterns.bg2.readItem().?;
                };
            }

            if ((self.tm.bg3 or self.ts.bg3) and self.bgmode.bg_mode < 2) {
                bg3_color = patterns.bg3.readItem() orelse blk: {
                    const data = self.fetchBG3Tile(lx, ly);
                    attributes.bg3 = data.@"1";
                    try patterns.bg3.write(&data.@"0");
                    if (lx == 0) {
                        for (0..(self.bg3hofs % 8)) |_| _ = patterns.bg3.readItem();
                    }
                    break :blk patterns.bg3.readItem().?;
                };
            }

            if ((self.tm.bg4 or self.ts.bg4) and self.bgmode.bg_mode == 0) {
                bg4_color = patterns.bg4.readItem() orelse blk: {
                    const data = self.fetchBG4Tile(lx, ly);
                    attributes.bg4 = data.@"1";
                    try patterns.bg4.write(&data.@"0");
                    if (lx == 0) {
                        for (0..(self.bg4hofs % 8)) |_| _ = patterns.bg4.readItem();
                    }
                    break :blk patterns.bg4.readItem().?;
                };
            }

            obj_color = patterns.obj[lx];

            obj_subcolor = obj_color;
            bg1_subcolor = bg1_color;
            bg2_subcolor = bg2_color;
            bg3_subcolor = bg3_color;
            bg4_subcolor = bg4_color;

            if (self.true_hires) {
                if (patterns.bg1.readItem()) |p| bg1_color = p;
                if (patterns.bg2.readItem()) |p| bg2_color = p;
            }
        } else {
            obj_color = patterns.obj[lx];
            obj_subcolor = obj_color;

            if (patterns.mode7[lx]) |cl| {
                bg1_color = if (self.cgwsel.direct_color_mode) directColor(0, cl) else @bitCast(self.cgram[cl]);
                bg1_subcolor = bg1_color;
            }

            if (self.setini.extbg) {
                if (patterns.mode7[lx]) |cl| {
                    bg2_color = @bitCast(self.cgram[cl & 0x7f]);
                    bg2_color.?.extbg_priority = (cl & 0x80) > 0;
                    bg2_subcolor = bg2_color;
                }
            }
        }

        const wnd1_in = lx >= self.wh0 and lx <= self.wh1;
        const wnd2_in = lx >= self.wh2 and lx <= self.wh3;

        var bg1_wnd = false;
        if (self.w12sel.bg1_wnd1_enable or self.w12sel.bg1_wnd2_enable) {
            const a = if (self.w12sel.bg1_wnd1_invert) !wnd1_in else wnd1_in;
            const b = if (self.w12sel.bg1_wnd2_invert) !wnd2_in else wnd2_in;
            if (!self.w12sel.bg1_wnd2_enable) {
                bg1_wnd = a;
            } else if (!self.w12sel.bg1_wnd1_enable) {
                bg1_wnd = b;
            } else {
                const wnd_in = switch (self.wbglog.bg1_wnd_mask) {
                    .OR => a or b,
                    .AND => a and b,
                    .XOR => (@intFromBool(a) ^ @intFromBool(b)) == 1,
                    .XNOR => (@intFromBool(a) ^ @intFromBool(b)) == 0,
                };
                bg1_wnd = wnd_in;
            }
        }

        var bg2_wnd = false;
        if (self.w12sel.bg2_wnd1_enable or self.w12sel.bg2_wnd2_enable) {
            const a = if (self.w12sel.bg2_wnd1_invert) !wnd1_in else wnd1_in;
            const b = if (self.w12sel.bg2_wnd2_invert) !wnd2_in else wnd2_in;
            if (!self.w12sel.bg2_wnd2_enable) {
                bg2_wnd = a;
            } else if (!self.w12sel.bg2_wnd1_enable) {
                bg2_wnd = b;
            } else {
                const wnd_in = switch (self.wbglog.bg2_wnd_mask) {
                    .OR => a or b,
                    .AND => a and b,
                    .XOR => (@intFromBool(a) ^ @intFromBool(b)) == 1,
                    .XNOR => (@intFromBool(a) ^ @intFromBool(b)) == 0,
                };
                bg2_wnd = wnd_in;
            }
        }

        var bg3_wnd = false;
        if (self.w34sel.bg3_wnd1_enable or self.w34sel.bg3_wnd2_enable) {
            const a = if (self.w34sel.bg3_wnd1_invert) !wnd1_in else wnd1_in;
            const b = if (self.w34sel.bg3_wnd2_invert) !wnd2_in else wnd2_in;
            if (!self.w34sel.bg3_wnd2_enable) {
                bg3_wnd = a;
            } else if (!self.w34sel.bg3_wnd1_enable) {
                bg3_wnd = b;
            } else {
                const wnd_in = switch (self.wbglog.bg3_wnd_mask) {
                    .OR => a or b,
                    .AND => a and b,
                    .XOR => (@intFromBool(a) ^ @intFromBool(b)) == 1,
                    .XNOR => (@intFromBool(a) ^ @intFromBool(b)) == 0,
                };
                bg3_wnd = wnd_in;
            }
        }

        var bg4_wnd = false;
        if (self.w34sel.bg4_wnd1_enable or self.w34sel.bg4_wnd2_enable) {
            const a = if (self.w34sel.bg4_wnd1_invert) !wnd1_in else wnd1_in;
            const b = if (self.w34sel.bg4_wnd2_invert) !wnd2_in else wnd2_in;
            if (!self.w34sel.bg4_wnd2_enable) {
                bg4_wnd = a;
            } else if (!self.w34sel.bg4_wnd1_enable) {
                bg4_wnd = b;
            } else {
                const wnd_in = switch (self.wbglog.bg4_wnd_mask) {
                    .OR => a or b,
                    .AND => a and b,
                    .XOR => (@intFromBool(a) ^ @intFromBool(b)) == 1,
                    .XNOR => (@intFromBool(a) ^ @intFromBool(b)) == 0,
                };
                bg4_wnd = wnd_in;
            }
        }

        var obj_wnd = false;
        if (self.wobjsel.obj_wnd1_enable or self.wobjsel.obj_wnd2_enable) {
            const a = if (self.wobjsel.obj_wnd1_invert) !wnd1_in else wnd1_in;
            const b = if (self.wobjsel.obj_wnd2_invert) !wnd2_in else wnd2_in;
            if (!self.wobjsel.obj_wnd2_enable) {
                obj_wnd = a;
            } else if (!self.wobjsel.obj_wnd1_enable) {
                obj_wnd = b;
            } else {
                const wnd_in = switch (self.wobjlog.obj_wnd_mask) {
                    .OR => a or b,
                    .AND => a and b,
                    .XOR => (@intFromBool(a) ^ @intFromBool(b)) == 1,
                    .XNOR => (@intFromBool(a) ^ @intFromBool(b)) == 0,
                };
                obj_wnd = wnd_in;
            }
        }

        var clr_wnd = false;
        if (self.wobjsel.clr_wnd1_enable or self.wobjsel.clr_wnd2_enable) {
            const a = if (self.wobjsel.clr_wnd1_invert) !wnd1_in else wnd1_in;
            const b = if (self.wobjsel.clr_wnd2_invert) !wnd2_in else wnd2_in;
            if (!self.wobjsel.clr_wnd2_enable) {
                clr_wnd = a;
            } else if (!self.wobjsel.clr_wnd1_enable) {
                clr_wnd = b;
            } else {
                const wnd_in = switch (self.wobjlog.clr_wnd_mask) {
                    .OR => a or b,
                    .AND => a and b,
                    .XOR => (@intFromBool(a) ^ @intFromBool(b)) == 1,
                    .XNOR => (@intFromBool(a) ^ @intFromBool(b)) == 0,
                };
                clr_wnd = wnd_in;
            }
        }

        if (self.tmw.bg1 and bg1_wnd) bg1_color = null;
        if (self.tmw.bg2 and bg2_wnd) bg2_color = null;
        if (self.tmw.bg3 and bg3_wnd) bg3_color = null;
        if (self.tmw.bg4 and bg4_wnd) bg4_color = null;
        if (self.tmw.obj and obj_wnd) obj_color = null;
        if (self.tsw.bg1 and bg1_wnd) bg1_subcolor = null;
        if (self.tsw.bg2 and bg2_wnd) bg2_subcolor = null;
        if (self.tsw.bg3 and bg3_wnd) bg3_subcolor = null;
        if (self.tsw.bg4 and bg4_wnd) bg4_subcolor = null;
        if (self.tsw.obj and obj_wnd) obj_subcolor = null;

        out_color = self.resolvePriority(
            self.tm,
            out_color,
            obj_color,
            bg1_color,
            bg2_color,
            bg3_color,
            bg4_color,
            attributes.obj_priorities[lx],
            attributes.bg1,
            attributes.bg2,
            attributes.bg3,
            attributes.bg4,
            &color_source,
        );

        sub_color = self.resolvePriority(
            if (self.true_hires) self.tm else self.ts,
            sub_color,
            obj_subcolor,
            bg1_subcolor,
            bg2_subcolor,
            bg3_subcolor,
            bg4_subcolor,
            attributes.obj_priorities[lx],
            attributes.bg1,
            attributes.bg2,
            attributes.bg3,
            attributes.bg4,
            &subcolor_source,
        );

        const black: CGDATA = .{ .red = 0, .green = 0, .blue = 0 };
        switch (self.cgwsel.mainscreen_wnd_black_region) {
            .nowhere => {},
            .outside_wnd => {
                if ((!self.wobjsel.clr_wnd1_enable and !self.wobjsel.clr_wnd2_enable) or !clr_wnd) {
                    out_color = black;
                    if (self.true_hires) sub_color = black;
                }
            },
            .inside_wnd => {
                if ((self.wobjsel.clr_wnd1_enable or self.wobjsel.clr_wnd2_enable) and clr_wnd) {
                    out_color = black;
                    if (self.true_hires) sub_color = black;
                }
            },
            .everywhere => {
                out_color = black;
                if (self.true_hires) sub_color = black;
            },
        }

        var transparent_subscreen = false;
        if (!self.true_hires) {
            switch (self.cgwsel.subscreen_wnd_transparent_region) {
                .nowhere => {},
                .outside_wnd => {
                    if ((!self.wobjsel.clr_wnd1_enable and !self.wobjsel.clr_wnd2_enable) or !clr_wnd) {
                        sub_color = black;
                        transparent_subscreen = true;
                    }
                },
                .inside_wnd => {
                    if ((self.wobjsel.clr_wnd1_enable or self.wobjsel.clr_wnd2_enable) and clr_wnd) {
                        sub_color = black;
                        transparent_subscreen = true;
                    }
                },
                .everywhere => {
                    sub_color = black;
                    transparent_subscreen = true;
                },
            }
        }

        if (self.true_hires) {
            self.framebuf[start_pos + lx * 2] = self.rgbcolor(
                self.colormath(
                    sub_color,
                    null,
                    false,
                    subcolor_source,
                    attributes.obj_opaques[lx],
                ),
            );
            self.framebuf[start_pos + lx * 2 + 1] = self.rgbcolor(
                self.colormath(
                    out_color,
                    null,
                    false,
                    color_source,
                    attributes.obj_opaques[lx],
                ),
            );
        } else if (self.setini.pseudo_hires) {
            const cl1: CGDATA = out_color orelse @bitCast(self.cgram[0]);
            const cl2: CGDATA = sub_color orelse @bitCast(self.cgram[0]);

            const cl: CGDATA = .{
                .red = @intCast((@as(u8, cl1.red) + @as(u8, cl2.red)) / 2),
                .green = @intCast((@as(u8, cl1.green) + @as(u8, cl2.green)) / 2),
                .blue = @intCast((@as(u8, cl1.blue) + @as(u8, cl2.blue)) / 2),
            };

            self.framebuf[start_pos + lx] = self.rgbcolor(
                self.colormath(
                    cl,
                    null,
                    transparent_subscreen,
                    color_source,
                    attributes.obj_opaques[lx],
                ),
            );
        } else {
            self.framebuf[start_pos + lx] = self.rgbcolor(
                self.colormath(
                    out_color,
                    sub_color,
                    transparent_subscreen,
                    color_source,
                    attributes.obj_opaques[lx],
                ),
            );
        }
    }

    pub fn process(self: *PPU) void {
        const vblank_scanline = @as(u16, if (self.setini.overscan) 240 else 225);
        self.extra_cpu_cycles = 0;

        self.cycle_counter -|= 1;
        if (self.cycle_counter > 0) return;

        self.cycle_counter = 4;

        var total_dots: u16 = 340;

        // V=311 --> long scanline in interlaced 50Hz field=1
        if (self.stat78.mode == .pal and self.setini.screen_interlacing and self.scanline == 311 and self.stat78.interlace_field == 1) {
            total_dots += 1;
        }

        // V=240 --> short scanline in non-interlaced 60Hz field=1
        if (!(self.stat78.mode == .ntsc and !self.setini.screen_interlacing and self.scanline == 240 and self.stat78.interlace_field == 1)) {
            // "normally dots 323 and 327 are 6 master cycles instead of 4"
            if (self.dot == 323 or self.dot == 327) self.cycle_counter += 2;
        }

        self.dot += 1;
        if (self.dot == total_dots) {
            self.dot = 0;
            self.scanline += 1;
        }

        // V=261/311 --> last line (in normal frames)
        var total_scanlines = @as(u16, if (self.stat78.mode == .ntsc) 262 else 312);

        // V=262/312 --> extra scanline (occurs only in interlace field=0)
        if (self.setini.screen_interlacing and self.stat78.interlace_field == 0) {
            total_scanlines += 1;
        }

        if (self.scanline == total_scanlines) {
            self.scanline = 0;
        }

        // V=0 --> end of vblank, toggle field
        if (self.scanline == 0) {
            // H=0, V=0 --> clear vblank flag and reset NMI flag (auto ack)
            if (self.dot == 0) {
                self.rdnmi.vblank = false;
                self.hvbjoy.vblank = false;

                // H=0?, V=0 --> reset OBJ overflow flags in 213Eh (only if not f-blank)
                if (!self.inidisp.forced_blanking) {
                    self.stat77.range_over = false;
                    self.stat77.time_over = false;
                }
            }

            // H=1, V=0 --> toggle interlace field flag
            if (self.dot == 1) {
                self.stat78.interlace_field = @as(u1, if (self.stat78.interlace_field == 0) 1 else 0);
            }

            // H=6, V=0 --> reload HDMA registers
            if (self.dot == 6) {
                self.dma.beginHdmaInit();
            }
        }

        // V=225/240 --> begin of vblank period (NMI, joypad read, reload OAMADD)
        if (self.scanline == vblank_scanline) {
            // H=0, V=225   --> set vblank flag
            // H=0.5, V=225 --> set NMI flag
            if (self.dot == 0) {
                self.hvbjoy.vblank = true;
                @memcpy(self.output, self.framebuf);
            }

            if (self.dot == 1) {
                self.rdnmi.vblank = true;
            }

            // H=10, V=225 --> reload OAMADD
            // "at begin of vblank, but only if not in forced blank mode, it reinitializes the address from the reload value"
            if (self.dot == 10 and !self.inidisp.forced_blanking) {
                self.oamadd = 0;
                self.oamadd |= @as(u9, self.oamaddl) << 1;
                self.oamadd |= @as(u10, if (self.oamaddh.address_high_bit > 0) 0x200 else 0);
            }

            // H=32.5..95.5, V=225 --> around here, joypad read begins
            if (self.dot == 33 and self.nmitimen.joypad_auto_read_enable) {
                self.hvbjoy.joypad_auto_read_in_progress = true;
                self.input.poll() catch unreachable;
                self.input.latch1.discard(self.input.latch1.count);
                self.input.latch2.discard(self.input.latch2.count);
            }
        }

        if (self.scanline == vblank_scanline + 3 and self.dot == 33) {
            self.hvbjoy.joypad_auto_read_in_progress = false;
        }

        // H=1 --> clear hblank flag
        if (self.dot == 1) {
            self.hvbjoy.hblank = false;
        }

        // H=274 --> set hblank flag
        if (self.dot == 274) {
            self.hvbjoy.hblank = true;
        }

        // H=133.5 --> around here, REFRESH begins (duration 40 clks/10 dots)
        if (self.dot == 134) {
            self.extra_cpu_cycles += 40;
        }

        if (self.scanline > 0 and self.scanline < vblank_scanline) {
            // H=22-277(?), V=1-224 --> draw picture
            if (self.dot >= 22 and self.dot <= 277) {
                self.draw() catch unreachable;
            }
        }

        if (self.scanline < vblank_scanline) {
            // H=278, V=0..224 --> perform HDMA transfers
            if (self.dot == 278) {
                self.dma.beginHdmaTransfer();
            }
        }

        switch (self.nmitimen.hv_timer_irq) {
            .h => {
                // H=HTIME+3.5 --> H-IRQ
                if (self.dot == self.htime + 4) self.irq_requested = true;
            },
            .v => {
                // H=2.5, V=VTIME --> V-IRQ (or HV-IRQ with HTIME=0)
                if (self.dot == 3 and self.scanline == self.vtime) self.irq_requested = true;
            },
            .hv => {
                // H=HTIME+3.5, V=VTIME --> HV-IRQ (when HTIME=1..339)
                if (self.htime == 0) {
                    if (self.dot == 3 and self.scanline == self.vtime) self.irq_requested = true;
                } else {
                    if (self.dot == self.htime + 4 and self.scanline == self.vtime) self.irq_requested = true;
                }
            },
            .off => {},
        }
    }

    pub fn reset(self: *PPU) void {
        @memset(self.framebuf, 0);
        @memset(self.output, 0);
        self.setini = @bitCast(@as(u8, 0));
        self.inidisp.forced_blanking = true;
        self.true_hires = false;
        self.irq_requested = false;
        self.nmitimen.nmi_enable = false;
        self.nmitimen.hv_timer_irq = .off;
        self.nmitimen.joypad_auto_read_enable = false;
        self.stat78.interlace_field = 0;
        self.rdnmi.vblank = false;
        self.wrio = 0xff;
        self.dot = 339;
        self.scanline = if (self.stat78.mode == .ntsc) 261 else 311;
        self.cycle_counter = 0;
        self.extra_cpu_cycles = 0;
        self.render_width.* = 256;
        self.render_height.* = 224;
    }

    pub fn serialize(self: *const PPU, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "oam");
        c.mpack_start_bin(pack, @intCast(self.oam.len));
        c.mpack_write_bytes(pack, self.oam.ptr, self.oam.len);
        c.mpack_finish_bin(pack);

        c.mpack_write_cstr(pack, "vram");
        c.mpack_build_array(pack);
        for (self.vram) |v| c.mpack_write_u16(pack, v);
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "cgram");
        c.mpack_build_array(pack);
        for (self.cgram) |v| c.mpack_write_u16(pack, v);
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "inidisp");
        c.mpack_write_u8(pack, @bitCast(self.inidisp));
        c.mpack_write_cstr(pack, "objsel");
        c.mpack_write_u8(pack, @bitCast(self.objsel));
        c.mpack_write_cstr(pack, "setini");
        c.mpack_write_u8(pack, @bitCast(self.setini));
        c.mpack_write_cstr(pack, "stat77");
        c.mpack_write_u8(pack, @bitCast(self.stat77));
        c.mpack_write_cstr(pack, "oamaddl");
        c.mpack_write_u8(pack, self.oamaddl);
        c.mpack_write_cstr(pack, "oamaddh");
        c.mpack_write_u8(pack, @bitCast(self.oamaddh));
        c.mpack_write_cstr(pack, "oamadd");
        c.mpack_write_u16(pack, self.oamadd);
        c.mpack_write_cstr(pack, "oamdata");
        c.mpack_write_u8(pack, self.oamdata);
        c.mpack_write_cstr(pack, "bgmode");
        c.mpack_write_u8(pack, @bitCast(self.bgmode));
        c.mpack_write_cstr(pack, "mosaic");
        c.mpack_write_u8(pack, @bitCast(self.mosaic));
        c.mpack_write_cstr(pack, "bg1sc");
        c.mpack_write_u8(pack, @bitCast(self.bg1sc));
        c.mpack_write_cstr(pack, "bg2sc");
        c.mpack_write_u8(pack, @bitCast(self.bg2sc));
        c.mpack_write_cstr(pack, "bg3sc");
        c.mpack_write_u8(pack, @bitCast(self.bg3sc));
        c.mpack_write_cstr(pack, "bg4sc");
        c.mpack_write_u8(pack, @bitCast(self.bg4sc));
        c.mpack_write_cstr(pack, "bg12nba");
        c.mpack_write_u8(pack, @bitCast(self.bg12nba));
        c.mpack_write_cstr(pack, "bg34nba");
        c.mpack_write_u8(pack, @bitCast(self.bg34nba));
        c.mpack_write_cstr(pack, "bg1hofs");
        c.mpack_write_u16(pack, self.bg1hofs);
        c.mpack_write_cstr(pack, "bg1vofs");
        c.mpack_write_u16(pack, self.bg1vofs);
        c.mpack_write_cstr(pack, "bg2hofs");
        c.mpack_write_u16(pack, self.bg2hofs);
        c.mpack_write_cstr(pack, "bg2vofs");
        c.mpack_write_u16(pack, self.bg2vofs);
        c.mpack_write_cstr(pack, "bg3hofs");
        c.mpack_write_u16(pack, self.bg3hofs);
        c.mpack_write_cstr(pack, "bg3vofs");
        c.mpack_write_u16(pack, self.bg3vofs);
        c.mpack_write_cstr(pack, "bg4hofs");
        c.mpack_write_u16(pack, self.bg4hofs);
        c.mpack_write_cstr(pack, "bg4vofs");
        c.mpack_write_u16(pack, self.bg4vofs);
        c.mpack_write_cstr(pack, "bgofs_latch");
        c.mpack_write_u8(pack, self.bgofs_latch);
        c.mpack_write_cstr(pack, "bghofs_latch");
        c.mpack_write_u8(pack, self.bghofs_latch);
        c.mpack_write_cstr(pack, "vmain");
        c.mpack_write_u8(pack, @bitCast(self.vmain));
        c.mpack_write_cstr(pack, "vmadd");
        c.mpack_write_u16(pack, self.vmadd);
        c.mpack_write_cstr(pack, "vmdata");
        c.mpack_write_u16(pack, self.vmdata);
        c.mpack_write_cstr(pack, "m7sel");
        c.mpack_write_u8(pack, @bitCast(self.m7sel));
        c.mpack_write_cstr(pack, "m7hofs");
        c.mpack_write_u16(pack, self.m7hofs);
        c.mpack_write_cstr(pack, "m7vofs");
        c.mpack_write_u16(pack, self.m7vofs);
        c.mpack_write_cstr(pack, "m7a");
        c.mpack_write_u16(pack, self.m7a);
        c.mpack_write_cstr(pack, "m7b");
        c.mpack_write_u16(pack, self.m7b);
        c.mpack_write_cstr(pack, "m7c");
        c.mpack_write_u16(pack, self.m7c);
        c.mpack_write_cstr(pack, "m7d");
        c.mpack_write_u16(pack, self.m7d);
        c.mpack_write_cstr(pack, "mpy");
        c.mpack_write_u32(pack, self.mpy);
        c.mpack_write_cstr(pack, "m7x");
        c.mpack_write_u16(pack, self.m7x);
        c.mpack_write_cstr(pack, "m7y");
        c.mpack_write_u16(pack, self.m7y);
        c.mpack_write_cstr(pack, "m7_latch");
        c.mpack_write_u8(pack, self.m7_latch);
        c.mpack_write_cstr(pack, "cgadd");
        c.mpack_write_u8(pack, self.cgadd);
        c.mpack_write_cstr(pack, "cgdata");
        c.mpack_write_u8(pack, self.cgdata);
        c.mpack_write_cstr(pack, "cgdata_l");
        c.mpack_write_bool(pack, self.cgdata_l);
        c.mpack_write_cstr(pack, "w12sel");
        c.mpack_write_u8(pack, @bitCast(self.w12sel));
        c.mpack_write_cstr(pack, "w34sel");
        c.mpack_write_u8(pack, @bitCast(self.w34sel));
        c.mpack_write_cstr(pack, "wobjsel");
        c.mpack_write_u8(pack, @bitCast(self.wobjsel));
        c.mpack_write_cstr(pack, "wbglog");
        c.mpack_write_u8(pack, @bitCast(self.wbglog));
        c.mpack_write_cstr(pack, "wobjlog");
        c.mpack_write_u8(pack, @bitCast(self.wobjlog));
        c.mpack_write_cstr(pack, "wh0");
        c.mpack_write_u8(pack, self.wh0);
        c.mpack_write_cstr(pack, "wh1");
        c.mpack_write_u8(pack, self.wh1);
        c.mpack_write_cstr(pack, "wh2");
        c.mpack_write_u8(pack, self.wh2);
        c.mpack_write_cstr(pack, "wh3");
        c.mpack_write_u8(pack, self.wh3);
        c.mpack_write_cstr(pack, "tm");
        c.mpack_write_u8(pack, @bitCast(self.tm));
        c.mpack_write_cstr(pack, "ts");
        c.mpack_write_u8(pack, @bitCast(self.ts));
        c.mpack_write_cstr(pack, "tmw");
        c.mpack_write_u8(pack, @bitCast(self.tmw));
        c.mpack_write_cstr(pack, "tsw");
        c.mpack_write_u8(pack, @bitCast(self.tsw));
        c.mpack_write_cstr(pack, "cgwsel");
        c.mpack_write_u8(pack, @bitCast(self.cgwsel));
        c.mpack_write_cstr(pack, "cgadsub");
        c.mpack_write_u8(pack, @bitCast(self.cgadsub));
        c.mpack_write_cstr(pack, "coldata");
        c.mpack_write_u16(pack, @bitCast(self.coldata));
        c.mpack_write_cstr(pack, "stat78");
        c.mpack_write_u8(pack, @bitCast(self.stat78));
        c.mpack_write_cstr(pack, "wrio");
        c.mpack_write_u8(pack, self.wrio);
        c.mpack_write_cstr(pack, "ophct");
        c.mpack_write_u16(pack, self.ophct);
        c.mpack_write_cstr(pack, "opvct");
        c.mpack_write_u16(pack, self.opvct);
        c.mpack_write_cstr(pack, "ophct_l");
        c.mpack_write_bool(pack, self.ophct_l);
        c.mpack_write_cstr(pack, "opvct_l");
        c.mpack_write_bool(pack, self.opvct_l);
        c.mpack_write_cstr(pack, "rdnmi");
        c.mpack_write_u8(pack, @bitCast(self.rdnmi));
        c.mpack_write_cstr(pack, "hvbjoy");
        c.mpack_write_u8(pack, @bitCast(self.hvbjoy));
        c.mpack_write_cstr(pack, "nmitimen");
        c.mpack_write_u8(pack, @bitCast(self.nmitimen));
        c.mpack_write_cstr(pack, "irq_requested");
        c.mpack_write_bool(pack, self.irq_requested);
        c.mpack_write_cstr(pack, "htime");
        c.mpack_write_u16(pack, self.htime);
        c.mpack_write_cstr(pack, "vtime");
        c.mpack_write_u16(pack, self.vtime);
        c.mpack_write_cstr(pack, "scanline");
        c.mpack_write_u16(pack, self.scanline);
        c.mpack_write_cstr(pack, "dot");
        c.mpack_write_u16(pack, self.dot);
        c.mpack_write_cstr(pack, "cycle_counter");
        c.mpack_write_u32(pack, self.cycle_counter);
        c.mpack_write_cstr(pack, "extra_cpu_cycles");
        c.mpack_write_u32(pack, self.extra_cpu_cycles);
        c.mpack_write_cstr(pack, "true_hires");
        c.mpack_write_bool(pack, self.true_hires);

        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *PPU, pack: c.mpack_node_t) void {
        @memset(self.oam, 0);
        @memset(self.vram, 0);
        @memset(self.cgram, 0);

        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "oam"), self.oam.ptr, self.oam.len);

        for (0..self.vram.len) |i| {
            self.vram[i] = c.mpack_node_u16(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "vram"), i));
        }

        for (0..self.cgram.len) |i| {
            self.cgram[i] = c.mpack_node_u16(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "cgram"), i));
        }

        self.inidisp = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "inidisp")));
        self.objsel = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "objsel")));
        self.setini = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "setini")));
        self.stat77 = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "stat77")));
        self.oamaddl = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "oamaddl"));
        self.oamaddh = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "oamaddh")));
        self.oamadd = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "oamadd")));
        self.oamdata = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "oamdata"));
        self.bgmode = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "bgmode")));
        self.mosaic = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "mosaic")));
        self.bg1sc = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "bg1sc")));
        self.bg2sc = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "bg2sc")));
        self.bg3sc = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "bg3sc")));
        self.bg4sc = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "bg4sc")));
        self.bg12nba = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "bg12nba")));
        self.bg34nba = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "bg34nba")));
        self.bg1hofs = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "bg1hofs")));
        self.bg1vofs = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "bg1vofs")));
        self.bg2hofs = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "bg2hofs")));
        self.bg2vofs = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "bg2vofs")));
        self.bg3hofs = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "bg3hofs")));
        self.bg3vofs = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "bg3vofs")));
        self.bg4hofs = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "bg4hofs")));
        self.bg4vofs = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "bg4vofs")));
        self.bgofs_latch = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "bgofs_latch"));
        self.bghofs_latch = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "bghofs_latch"));
        self.vmain = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "vmain")));
        self.vmadd = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "vmadd"));
        self.vmdata = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "vmdata"));
        self.m7sel = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "m7sel")));
        self.m7hofs = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "m7hofs")));
        self.m7vofs = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "m7vofs")));
        self.m7a = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "m7a"));
        self.m7b = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "m7b"));
        self.m7c = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "m7c"));
        self.m7d = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "m7d"));
        self.mpy = @truncate(c.mpack_node_u32(c.mpack_node_map_cstr(pack, "mpy")));
        self.m7x = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "m7x")));
        self.m7y = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "m7y")));
        self.m7_latch = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "m7_latch"));
        self.cgadd = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "cgadd"));
        self.cgdata = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "cgdata"));
        self.cgdata_l = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "cgdata_l"));
        self.w12sel = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "w12sel")));
        self.w34sel = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "w34sel")));
        self.wobjsel = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "wobjsel")));
        self.wbglog = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "wbglog")));
        self.wobjlog = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "wobjlog")));
        self.wh0 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "wh0"));
        self.wh1 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "wh1"));
        self.wh2 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "wh2"));
        self.wh3 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "wh3"));
        self.tm = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "tm")));
        self.ts = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ts")));
        self.tmw = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "tmw")));
        self.tsw = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "tsw")));
        self.cgwsel = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "cgwsel")));
        self.cgadsub = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "cgadsub")));
        self.coldata = @bitCast(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "coldata")));
        self.stat78 = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "stat78")));
        self.wrio = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "wrio"));
        self.ophct = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "ophct"));
        self.opvct = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "opvct"));
        self.ophct_l = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "ophct_l"));
        self.opvct_l = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "opvct_l"));
        self.rdnmi = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "rdnmi")));
        self.hvbjoy = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "hvbjoy")));
        self.nmitimen = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "nmitimen")));
        self.irq_requested = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "irq_requested"));
        self.htime = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "htime")));
        self.vtime = @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "vtime")));
        self.scanline = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "scanline"));
        self.dot = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "dot"));
        self.cycle_counter = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "cycle_counter"));
        self.extra_cpu_cycles = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "extra_cpu_cycles"));
        self.true_hires = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "true_hires"));
    }

    pub fn memory(self: *@This()) Memory(u24, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinitMemory,
            },
        };
    }
};

const ColorSource = enum { bg1, bg2, bg3, bg4, obj, backdrop };

const BGMapAttr = packed struct {
    tile_index: u10,
    palette: u3,
    priority: bool,
    flip_h: bool,
    flip_v: bool,
};

const Mode7Addr = packed struct {
    unused: u8,
    pixel_index: u3,
    map_index: u7,
    zero: u14,
};

const OffsetPerTile = packed struct {
    scroll_offset: u10,
    unused: u3,
    apply_bg1: bool,
    apply_bg2: bool,
    hv: enum(u1) { h = 0, v },
};

const OAM = packed struct {
    pos_x: u8,
    pos_y: u8,
    tile_index: u8,
    name_select: bool,
    palette: u3,
    priority: u2,
    flip_h: bool,
    flip_v: bool,
};

const OAMAux = packed struct {
    posx_0: u1,
    size_0: u1,
    posx_1: u1,
    size_1: u1,
    posx_2: u1,
    size_2: u1,
    posx_3: u1,
    size_3: u1,
};

const OAMEntry = struct {
    oam: OAM,
    width: usize,
    height: usize,
    pos_x: i9,
    offset_y: usize,
};

const INIDISP = packed struct {
    brightness: u4,
    unused: u3,
    forced_blanking: bool,
};

const OBJSEL = packed struct {
    name_base_address: u3,
    name_secondary_select: u2,
    obj_sprite_size: enum(u3) {
        s8x8_16x16 = 0,
        s8x8_32x32,
        s8x8_64x64,
        s16x16_32x32,
        s16x16_64x64,
        s32x32_64x64,
        s16x32_32x64,
        s16x32_32x32,
    },
};

const OAMADDH = packed struct {
    address_high_bit: u1,
    unused: u6,
    priority_rotation: bool,
};

const BGCharSize = enum(u1) { s8x8 = 0, s16x16 = 1 };

const BGMODE = packed struct {
    bg_mode: u3,
    mode1_bg3_priority: bool,
    bg1_char_size: BGCharSize,
    bg2_char_size: BGCharSize,
    bg3_char_size: BGCharSize,
    bg4_char_size: BGCharSize,
};

const MOSAIC = packed struct {
    bg1_enable: bool,
    bg2_enable: bool,
    bg3_enable: bool,
    bg4_enable: bool,
    size: u4,
};

const BGSC = packed struct {
    large_horizontal: bool,
    large_vertical: bool,
    tilemap_address: u6,
};

const BG12NBA = packed struct {
    bg1_chr_base_address: u4,
    bg2_chr_base_address: u4,
};

const BG34NBA = packed struct {
    bg3_chr_base_address: u4,
    bg4_chr_base_address: u4,
};

const VMAIN = packed struct {
    increment_size: enum(u2) { w1 = 0, w32, w128, w128_2 },
    remapping: enum(u2) { none, b8, b9, b10 },
    unused: u3,
    address_increment_mode: enum(u1) { low = 0, high },
};

const M7SEL = packed struct {
    flip_h: bool,
    flip_v: bool,
    unused: u4,
    fill: bool,
    tilemap_norepeat: bool,
};

const CGDATA = packed struct {
    red: u5,
    green: u5,
    blue: u5,
    extbg_priority: bool = false,
};

const W12SEL = packed struct {
    bg1_wnd1_invert: bool,
    bg1_wnd1_enable: bool,
    bg1_wnd2_invert: bool,
    bg1_wnd2_enable: bool,
    bg2_wnd1_invert: bool,
    bg2_wnd1_enable: bool,
    bg2_wnd2_invert: bool,
    bg2_wnd2_enable: bool,
};

const W34SEL = packed struct {
    bg3_wnd1_invert: bool,
    bg3_wnd1_enable: bool,
    bg3_wnd2_invert: bool,
    bg3_wnd2_enable: bool,
    bg4_wnd1_invert: bool,
    bg4_wnd1_enable: bool,
    bg4_wnd2_invert: bool,
    bg4_wnd2_enable: bool,
};

const WOBJSEL = packed struct {
    obj_wnd1_invert: bool,
    obj_wnd1_enable: bool,
    obj_wnd2_invert: bool,
    obj_wnd2_enable: bool,
    clr_wnd1_invert: bool,
    clr_wnd1_enable: bool,
    clr_wnd2_invert: bool,
    clr_wnd2_enable: bool,
};

const BGWndMask = enum(u2) { OR = 0, AND, XOR, XNOR };

const WBGLOG = packed struct {
    bg1_wnd_mask: BGWndMask,
    bg2_wnd_mask: BGWndMask,
    bg3_wnd_mask: BGWndMask,
    bg4_wnd_mask: BGWndMask,
};

const WOBJLOG = packed struct {
    obj_wnd_mask: BGWndMask,
    clr_wnd_mask: BGWndMask,
    unused: u4,
};

const TMTS = packed struct {
    bg1: bool,
    bg2: bool,
    bg3: bool,
    bg4: bool,
    obj: bool,
    unused: u3,
};

const CGWSELRegion = enum(u2) { nowhere = 0, outside_wnd, inside_wnd, everywhere };

const CGWSEL = packed struct {
    direct_color_mode: bool,
    add_subscreen: bool,
    unused: u2,
    subscreen_wnd_transparent_region: CGWSELRegion,
    mainscreen_wnd_black_region: CGWSELRegion,
};

const CGADSUB = packed struct {
    bg1_math: bool,
    bg2_math: bool,
    bg3_math: bool,
    bg4_math: bool,
    obj_math: bool,
    backdrop_math: bool,
    half_math: bool,
    subtract: bool,
};

const COLDATA = packed struct {
    color: u5,
    red: bool,
    green: bool,
    blue: bool,
};

const SETINI = packed struct {
    screen_interlacing: bool,
    obj_interlacing: bool,
    overscan: bool,
    pseudo_hires: bool,
    unused: u2,
    extbg: bool,
    external_sync: bool,
};

const STAT77 = packed struct {
    ppu1_version: u4,
    ppu1_openbus: u1,
    master_mode: bool,
    range_over: bool,
    time_over: bool,
};

const STAT78 = packed struct {
    ppu2_version: u4,
    mode: enum(u1) { ntsc = 0, pal },
    ppu2_openbus: u1,
    counter_latch: bool,
    interlace_field: u1,
};

const NMITIMEN = packed struct {
    joypad_auto_read_enable: bool,
    unused: u3,
    hv_timer_irq: enum(u2) { off = 0, h, v, hv },
    unused_2: u1,
    nmi_enable: bool,
};

const RDNMI = packed struct {
    cpu_version: u4,
    openbus: u3,
    vblank: bool,
};

const HVBJOY = packed struct {
    joypad_auto_read_in_progress: bool,
    openbus: u5,
    hblank: bool,
    vblank: bool,
};
