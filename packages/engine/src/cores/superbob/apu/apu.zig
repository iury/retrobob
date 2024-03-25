const std = @import("std");
const DSP = @import("dsp.zig").DSP;
const Memory = @import("../../../memory.zig").Memory;
const IO = @import("../io.zig").IO;
const opcode = @import("opcode.zig");
const c = @import("../../../c.zig");

const Timer = struct {
    rate: u8,

    output: u4 = 0xf,
    target: u8 = 0,
    enabled: bool = false,

    stage0: u8 = 0,
    stage1: bool = false,
    prev_stage1: bool = false,
    stage2: u8 = 0,

    pub fn tick(self: *@This()) void {
        const curr = self.stage1;
        const prev = self.prev_stage1;
        self.prev_stage1 = self.stage1;

        // only clock on 1->0 transitions, when the timer is enabled
        if (!self.enabled or !prev or curr) return;

        self.stage2 +%= 1;
        if (self.stage2 == self.target) {
            self.stage2 = 0;
            self.output +%= 1;
        }
    }

    pub fn setEnabled(self: *@This(), enabled: bool) void {
        if (!self.enabled and enabled) {
            self.stage2 = 0;
            self.output = 0;
        }
        self.enabled = enabled;
    }

    pub fn process(self: *@This()) void {
        self.stage0 += 2;
        if (self.stage0 >= self.rate) {
            self.stage1 = !self.stage1;
            self.stage0 -= self.rate;
            self.tick();
        }
    }

    pub fn serialize(self: *const Timer, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);
        c.mpack_write_cstr(pack, "output");
        c.mpack_write_u8(pack, self.output);
        c.mpack_write_cstr(pack, "target");
        c.mpack_write_u8(pack, self.target);
        c.mpack_write_cstr(pack, "enabled");
        c.mpack_write_bool(pack, self.enabled);
        c.mpack_write_cstr(pack, "stage0");
        c.mpack_write_u8(pack, self.stage0);
        c.mpack_write_cstr(pack, "stage1");
        c.mpack_write_bool(pack, self.stage1);
        c.mpack_write_cstr(pack, "prev_stage1");
        c.mpack_write_bool(pack, self.prev_stage1);
        c.mpack_write_cstr(pack, "stage2");
        c.mpack_write_u8(pack, self.stage2);
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *Timer, pack: c.mpack_node_t) void {
        self.output = @truncate(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "output")));
        self.target = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "target"));
        self.enabled = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "enabled"));
        self.stage0 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "stage0"));
        self.stage1 = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "stage1"));
        self.prev_stage1 = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "prev_stage1"));
        self.stage2 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "stage2"));
    }
};

pub const APU = struct {
    allocator: std.mem.Allocator,
    ram: []u8,
    dsp: *DSP,

    apuio0: u8 = 0,
    apuio1: u8 = 0,
    apuio2: u8 = 0,
    apuio3: u8 = 0,

    timer0: Timer = .{ .rate = 128 },
    timer1: Timer = .{ .rate = 128 },
    timer2: Timer = .{ .rate = 16 },

    pc: u16 = 0xffc0,
    sp: u8 = 0xff,
    acc: u8 = 0,
    x: u8 = 0,
    y: u8 = 0,
    psw: PSW = @bitCast(@as(u8, 0)),

    halt: bool = false,
    cycle_counter: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) !*APU {
        const instance = try allocator.create(APU);
        instance.* = .{
            .allocator = allocator,
            .ram = try allocator.alloc(u8, 0x10000),
            .dsp = undefined,
        };
        instance.dsp = try DSP.init(allocator, instance.ram);
        instance.reset();
        return instance;
    }

    pub fn deinit(self: *APU) void {
        self.dsp.deinit();
        self.allocator.free(self.ram);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn mmio_read(ctx: *anyopaque, address: u24) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const v = switch (address) {
            @intFromEnum(IO.APUIO0) => self.apuio0,
            @intFromEnum(IO.APUIO1) => self.apuio1,
            @intFromEnum(IO.APUIO2) => self.apuio2,
            @intFromEnum(IO.APUIO3) => self.apuio3,
            else => 0,
        };
        return v;
    }

    pub fn mmio_write(ctx: *anyopaque, address: u24, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        switch (address) {
            @intFromEnum(IO.APUIO0) => self.ram[0xf4] = value,
            @intFromEnum(IO.APUIO1) => self.ram[0xf5] = value,
            @intFromEnum(IO.APUIO2) => self.ram[0xf6] = value,
            @intFromEnum(IO.APUIO3) => self.ram[0xf7] = value,
            else => {},
        }
    }

    fn read(self: *APU, address: u16) u8 {
        return switch (address) {
            0xf0, 0xf1, 0xfa, 0xfb, 0xfc => 0,

            0xf2 => self.ram[0xf2] & 0x7f,
            0xf3 => self.dsp.read(self.ram[0xf2] & 0x7f),

            0xfd => blk: {
                const v = self.timer0.output;
                self.timer0.output = 0;
                break :blk v;
            },

            0xfe => blk: {
                const v = self.timer1.output;
                self.timer1.output = 0;
                break :blk v;
            },

            0xff => blk: {
                const v = self.timer2.output;
                self.timer2.output = 0;
                break :blk v;
            },

            0xffc0...0xffff => blk: {
                if ((self.ram[0xf1] & 0x80) == 0) {
                    break :blk self.ram[address];
                } else {
                    break :blk BOOT_ROM[address % BOOT_ROM.len];
                }
            },

            else => self.ram[address],
        };
    }

    fn write(self: *APU, address: u16, value: u8) void {
        switch (address) {
            0xfd, 0xfe, 0xff => {},

            0xf1 => {
                self.ram[0xf1] = value;

                self.timer0.setEnabled((value & 0x1) > 0);
                self.timer1.setEnabled((value & 0x2) > 0);
                self.timer2.setEnabled((value & 0x4) > 0);

                if ((value & 0x10) > 0) {
                    self.apuio0 = 0;
                    self.apuio1 = 0;
                }

                if ((value & 0x20) > 0) {
                    self.apuio2 = 0;
                    self.apuio3 = 0;
                }
            },

            0xf3 => {
                if ((self.ram[0xf2] & 0x80) == 0) {
                    self.dsp.write(self.ram[0xf2], value);
                }
            },

            0xf4 => self.apuio0 = value,
            0xf5 => self.apuio1 = value,
            0xf6 => self.apuio2 = value,
            0xf7 => self.apuio3 = value,

            0xfa => self.timer0.target = value,
            0xfb => self.timer1.target = value,
            0xfc => self.timer2.target = value,

            else => self.ram[address] = value,
        }
    }

    fn translateIndirect(self: *APU, d: u8) u16 {
        const db: u16 = if (self.psw.p) 0x100 else 0;
        var addr: u8 = d;
        const l = self.read(db | addr);
        addr +%= 1;
        const h: u16 = self.read(db | addr);
        return (h << 8) | l;
    }

    pub fn process(self: *APU) void {
        self.dsp.process();
        self.timer0.process();
        self.timer1.process();
        self.timer2.process();

        if (self.halt) return;

        self.cycle_counter -|= 1;
        if (self.cycle_counter > 0) return;

        const code = self.read(self.pc);
        const op = opcode.Opcodes[code];

        self.pc +%= 1;

        var arg8: u8 = 0;
        if (op.length >= 2) {
            arg8 = self.read(self.pc);
            self.pc +%= 1;
        }

        var arg: u16 = arg8;
        if (op.length == 3) {
            arg |= @as(u16, self.read(self.pc)) << 8;
            self.pc +%= 1;
        }

        self.cycle_counter = op.cycles;
        const db: u16 = if (self.psw.p) 0x100 else 0;

        switch (op.instruction) {
            .ADC => {
                var a: u8 = 0;
                var b: u8 = 0;
                const cc: u8 = if (self.psw.c) 1 else 0;
                var result: u8 = 0;
                var carried = false;
                switch (code) {
                    //  ADC   (X), (Y)     99    1     5   (X) = (X)+(Y)+C                  NV..H.ZC
                    0x99 => {
                        a = self.read(db + self.x);
                        b = self.read(db + self.y);
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.write(db + self.x, result);
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    //  ADC   A, #i        88    2     2   A = A+i+C                        NV..H.ZC
                    0x88 => {
                        a = self.acc;
                        b = @intCast(arg);
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.acc = result;
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    //  ADC   A, (X)       86    1     3   A = A+(X)+C                      NV..H.ZC
                    0x86 => {
                        a = self.acc;
                        b = self.read(db + self.x);
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.acc = result;
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    //  ADC   A, [d]+Y     97    2     6   A = A+([d]+Y)+C                  NV..H.ZC
                    0x97 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8) +% self.y);
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.acc = result;
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    //  ADC   A, [d+X]     87    2     6   A = A+([d+X])+C                  NV..H.ZC
                    0x87 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8 +% self.x));
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.acc = result;
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    //  ADC   A, d         84    2     3   A = A+(d)+C                      NV..H.ZC
                    0x84 => {
                        a = self.acc;
                        b = self.read(db + arg);
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.acc = result;
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    //  ADC   A, d+X       94    2     4   A = A+(d+X)+C                    NV..H.ZC
                    0x94 => {
                        a = self.acc;
                        b = self.read(db + @as(u16, arg8 +% self.x));
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.acc = result;
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    //  ADC   A, !a        85    3     4   A = A+(a)+C                      NV..H.ZC
                    0x85 => {
                        a = self.acc;
                        b = self.read(arg);
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.acc = result;
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    //  ADC   A, !a+X      95    3     5   A = A+(a+X)+C                    NV..H.ZC
                    0x95 => {
                        a = self.acc;
                        b = self.read(arg +% self.x);
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.acc = result;
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    //  ADC   A, !a+Y      96    3     5   A = A+(a+Y)+C                    NV..H.ZC
                    0x96 => {
                        a = self.acc;
                        b = self.read(arg +% self.y);
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.acc = result;
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    //  ADC   dd, ds       89    3     6   (dd) = (dd)+(d)+C                NV..H.ZC
                    0x89 => {
                        a = self.read(db + (arg >> 8));
                        b = self.read(db + (arg & 0xff));
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.write(db + (arg >> 8), result);
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    //  ADC   d, #i        98    3     5   (d) = (d)+i+C                    NV..H.ZC
                    0x98 => {
                        a = self.read(db + (arg >> 8));
                        b = @intCast(arg & 0xff);
                        const add1 = @addWithOverflow(a, b);
                        const add2 = @addWithOverflow(add1.@"0", cc);
                        result = add2.@"0";
                        self.write(db + (arg >> 8), result);
                        carried = add1.@"1" == 1 or add2.@"1" == 1;
                    },
                    else => {},
                }
                self.psw.z = result == 0;
                self.psw.n = (result & 0x80) > 0;
                self.psw.c = carried;
                self.psw.v = ((a ^ result) & (b ^ result) & 0x80) > 0;
                self.psw.h = (a ^ b ^ cc ^ result) & 0x10 != 0;
            },

            .ADDW => {
                // ADDW  YA, d        7A    2     5   YA  = YA + (d), H on high byte   NV..H.ZC
                const a = (@as(u16, self.y) << 8) | self.acc;
                const b = self.translateIndirect(arg8);
                const add = @addWithOverflow(a, b);
                const result = add.@"0";
                self.y = @intCast(result >> 8);
                self.acc = @intCast(result & 0xff);
                self.psw.z = result == 0;
                self.psw.n = (result & 0x8000) > 0;
                self.psw.c = add.@"1" == 1;
                self.psw.v = ((a ^ result) & (b ^ result) & 0x8000) > 0;
                self.psw.h = (a ^ b ^ result) & 0x1000 != 0;
            },

            .AND => {
                var a: u8 = 0;
                var b: u8 = 0;
                var result: u8 = 0;
                switch (code) {
                    // AND   (X), (Y)     39    1     5   (X) = (X) & (Y)                  N.....Z.
                    0x39 => {
                        a = self.read(db + self.x);
                        b = self.read(db + self.y);
                        result = a & b;
                        self.write(db + self.x, result);
                    },
                    // AND   A, #i        28    2     2   A = A & i                        N.....Z.
                    0x28 => {
                        a = self.acc;
                        b = @intCast(arg);
                        result = a & b;
                        self.acc = result;
                    },
                    // AND   A, (X)       26    1     3   A = A & (X)                      N.....Z.
                    0x26 => {
                        a = self.acc;
                        b = self.read(db + self.x);
                        result = a & b;
                        self.acc = result;
                    },
                    // AND   A, [d]+Y     37    2     6   A = A & ([d]+Y)                  N.....Z.
                    0x37 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8) +% self.y);
                        result = a & b;
                        self.acc = result;
                    },
                    // AND   A, [d+X]     27    2     6   A = A & ([d+X])                  N.....Z.
                    0x27 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8 +% self.x));
                        result = a & b;
                        self.acc = result;
                    },
                    // AND   A, d         24    2     3   A = A & (d)                      N.....Z.
                    0x24 => {
                        a = self.acc;
                        b = self.read(db + arg);
                        result = a & b;
                        self.acc = result;
                    },
                    // AND   A, d+X       34    2     4   A = A & (d+X)                    N.....Z.
                    0x34 => {
                        a = self.acc;
                        b = self.read(db + @as(u16, arg8 +% self.x));
                        result = a & b;
                        self.acc = result;
                    },
                    // AND   A, !a        25    3     4   A = A & (a)                      N.....Z.
                    0x25 => {
                        a = self.acc;
                        b = self.read(arg);
                        result = a & b;
                        self.acc = result;
                    },
                    // AND   A, !a+X      35    3     5   A = A & (a+X)                    N.....Z.
                    0x35 => {
                        a = self.acc;
                        b = self.read(arg +% @as(u16, self.x));
                        result = a & b;
                        self.acc = result;
                    },
                    // AND   A, !a+Y      36    3     5   A = A & (a+Y)                    N.....Z.
                    0x36 => {
                        a = self.acc;
                        b = self.read(arg +% @as(u16, self.y));
                        result = a & b;
                        self.acc = result;
                    },
                    // AND   dd, ds       29    3     6   (dd) = (dd) & (ds)               N.....Z.
                    0x29 => {
                        a = self.read(db + (arg >> 8));
                        b = self.read(db + (arg & 0xff));
                        result = a & b;
                        self.write(db + (arg >> 8), result);
                    },
                    // AND   d, #i        38    3     5   (d) = (d) & i                    N.....Z.
                    0x38 => {
                        a = self.read(db + (arg >> 8));
                        b = @intCast(arg & 0xff);
                        result = a & b;
                        self.write(db + (arg >> 8), result);
                    },
                    else => {},
                }
                self.psw.n = (result & 0x80) > 0;
                self.psw.z = result == 0;
            },

            .AND1 => {
                const b: u3 = @intCast(arg >> 13);
                var v = self.read(arg & 0x1fff);
                v &= switch (b) {
                    0 => 0x01,
                    1 => 0x02,
                    2 => 0x04,
                    3 => 0x08,
                    4 => 0x10,
                    5 => 0x20,
                    6 => 0x40,
                    7 => 0x80,
                };

                // AND1  C, /m.b      6A    3     4   C = C & ~(m.b)                   .......C
                if (code == 0x6a) {
                    self.psw.c = self.psw.c and (v == 0);
                }

                // AND1  C, m.b       4A    3     4   C = C & (m.b)                    .......C
                if (code == 0x4a) {
                    self.psw.c = self.psw.c and (v > 0);
                }
            },

            .ASL => {
                var v: u8 = 0;
                switch (code) {
                    // ASL   A            1C    1     2   Left shift A: high->C, 0->low    N.....ZC
                    0x1C => {
                        self.psw.c = (self.acc & 0x80) > 0;
                        self.acc <<= 1;
                        v = self.acc;
                    },
                    // ASL   d            0B    2     4   Left shift (d) as above          N.....ZC
                    0x0B => {
                        v = self.read(db + arg);
                        self.psw.c = (v & 0x80) > 0;
                        v <<= 1;
                        self.write(db + arg, v);
                    },
                    // ASL   d+X          1B    2     5   Left shift (d+X) as above        N.....ZC
                    0x1B => {
                        v = self.read(db + @as(u16, arg8 +% self.x));
                        self.psw.c = (v & 0x80) > 0;
                        v <<= 1;
                        self.write(db + @as(u16, arg8 +% self.x), v);
                    },
                    // ASL   !a           0C    3     5   Left shift (a) as above          N.....ZC
                    0x0C => {
                        v = self.read(arg);
                        self.psw.c = (v & 0x80) > 0;
                        v <<= 1;
                        self.write(arg, v);
                    },
                    else => {},
                }
                self.psw.n = (v & 0x80) > 0;
                self.psw.z = v == 0;
            },

            .BBC => {
                // BBC   d.0, r       13    3    5/7  PC+=r  if d.0 == 0               ........
                var v = self.read(db + (arg & 0xff));
                v &= switch (code) {
                    0x13 => 0x01,
                    0x33 => 0x02,
                    0x53 => 0x04,
                    0x73 => 0x08,
                    0x93 => 0x10,
                    0xB3 => 0x20,
                    0xD3 => 0x40,
                    0xF3 => 0x80,
                    else => 0,
                };
                if (v == 0) {
                    self.cycle_counter += 2;
                    self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(@as(u8, @intCast(arg >> 8)))))));
                }
            },

            .BBS => {
                // BBS   d.0, r       03    3    5/7  PC+=r  if d.0 == 1               ........
                var v = self.read(db + (arg & 0xff));
                v &= switch (code) {
                    0x03 => 0x01,
                    0x23 => 0x02,
                    0x43 => 0x04,
                    0x63 => 0x08,
                    0x83 => 0x10,
                    0xA3 => 0x20,
                    0xC3 => 0x40,
                    0xE3 => 0x80,
                    else => 0,
                };
                if (v > 0) {
                    self.cycle_counter += 2;
                    self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(@as(u8, @intCast(arg >> 8)))))));
                }
            },

            .BCC => {
                // BCC   r            90    2    2/4  PC+=r  if C == 0                 ........
                if (!self.psw.c) {
                    self.cycle_counter += 2;
                    self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(arg8)))));
                }
            },

            .BCS => {
                // BCS   r            B0    2    2/4  PC+=r  if C == 1                 ........
                if (self.psw.c) {
                    self.cycle_counter += 2;
                    self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(arg8)))));
                }
            },

            .BEQ => {
                // BEQ   r            F0    2    2/4  PC+=r  if Z == 1                 ........
                if (self.psw.z) {
                    self.cycle_counter += 2;
                    self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(arg8)))));
                }
            },

            .BMI => {
                // BMI   r            30    2    2/4  PC+=r  if N == 1                 ........
                if (self.psw.n) {
                    self.cycle_counter += 2;
                    self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(arg8)))));
                }
            },

            .BNE => {
                // BNE   r            D0    2    2/4  PC+=r  if Z == 0                 ........
                if (!self.psw.z) {
                    self.cycle_counter += 2;
                    self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(arg8)))));
                }
            },

            .BPL => {
                // BPL   r            10    2    2/4  PC+=r  if N == 0                 ........
                if (!self.psw.n) {
                    self.cycle_counter += 2;
                    self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(arg8)))));
                }
            },

            .BVC => {
                // BVC   r            50    2    2/4  PC+=r  if V == 0                 ........
                if (!self.psw.v) {
                    self.cycle_counter += 2;
                    self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(arg8)))));
                }
            },

            .BVS => {
                // BVS   r            70    2    2/4  PC+=r  if V == 1                 ........
                if (self.psw.v) {
                    self.cycle_counter += 2;
                    self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(arg8)))));
                }
            },

            .BRA => {
                // BRA   r            2F    2     4   PC+=r                            ........
                self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(arg8)))));
            },

            .BRK => {
                // BRK                0F    1     8   Push PC and Flags, PC = [$FFDE]  ...1.0..
                self.write(0x100 | @as(u16, self.sp), @intCast(self.pc >> 8));
                self.sp -%= 1;
                self.write(0x100 | @as(u16, self.sp), @intCast(self.pc & 0xff));
                self.sp -%= 1;
                self.write(0x100 | @as(u16, self.sp), @bitCast(self.psw));
                self.sp -%= 1;
                self.psw.i = false;
                self.psw.b = true;
                const v = @as(u16, 0xffde);
                self.pc = @as(u16, self.read(v + 1)) << 8 | self.read(v);
            },

            .CALL => {
                // CALL  !a           3F    3     8   (SP--)=PCh, (SP--)=PCl, PC=a     ........
                self.write(0x100 | @as(u16, self.sp), @intCast(self.pc >> 8));
                self.sp -%= 1;
                self.write(0x100 | @as(u16, self.sp), @intCast(self.pc & 0xff));
                self.sp -%= 1;
                self.pc = arg;
            },

            .CBNE => {
                var v: u8 = 0;
                // CBNE  d+X, r       DE    3    6/8  CMP A, (d+X) then BNE            ........
                if (code == 0xde) {
                    v = self.read(db + @as(u16, @as(u8, @intCast(arg & 0xff)) +% self.x));
                }
                // CBNE  d, r         2E    3    5/7  CMP A, (d) then BNE              ........
                if (code == 0x2e) {
                    v = self.read(db + @as(u8, @intCast(arg & 0xff)));
                }

                if (self.acc != v) {
                    self.cycle_counter += 2;
                    self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(@as(u8, @intCast(arg >> 8)))))));
                }
            },

            .CLR1 => {
                // CLR1  d.n          12    2     4   d.n = 0                          ........
                var v = self.read(db + arg);
                v &= switch (code) {
                    0x12 => 0xfe,
                    0x32 => 0xfd,
                    0x52 => 0xfb,
                    0x72 => 0xf7,
                    0x92 => 0xef,
                    0xB2 => 0xdf,
                    0xD2 => 0xbf,
                    0xF2 => 0x7f,
                    else => 0,
                };
                self.write(db + arg, v);
            },

            .CLRC => {
                // CLRC               60    1     2   C = 0                            .......0
                self.psw.c = false;
            },

            .CLRP => {
                // CLRP               20    1     2   P = 0                            ..0.....
                self.psw.p = false;
            },

            .CLRV => {
                // CLRV               E0    1     2   V = 0, H = 0                     .0..0...
                self.psw.v = false;
                self.psw.h = false;
            },

            .CMP => {
                var a: u8 = 0;
                var b: u8 = 0;
                switch (code) {
                    // CMP   (X), (Y)     79    1     5   (X) - (Y)                        N.....ZC
                    0x79 => {
                        a = self.read(db + self.x);
                        b = self.read(db + self.y);
                    },
                    // CMP   A, #i        68    2     2   A - i                            N.....ZC
                    0x68 => {
                        a = self.acc;
                        b = @intCast(arg);
                    },
                    // CMP   A, (X)       66    1     3   A - (X)                          N.....ZC
                    0x66 => {
                        a = self.acc;
                        b = self.read(db + self.x);
                    },
                    // CMP   A, [d]+Y     77    2     6   A - ([d]+Y)                      N.....ZC
                    0x77 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8) +% self.y);
                    },
                    // CMP   A, [d+X]     67    2     6   A - ([d+X])                      N.....ZC
                    0x67 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8 +% self.x));
                    },
                    // CMP   A, d         64    2     3   A - (d)                          N.....ZC
                    0x64 => {
                        a = self.acc;
                        b = self.read(db + arg);
                    },
                    // CMP   A, d+X       74    2     4   A - (d+X)                        N.....ZC
                    0x74 => {
                        a = self.acc;
                        b = self.read(db + @as(u16, arg8 +% self.x));
                    },
                    // CMP   A, !a        65    3     4   A - (a)                          N.....ZC
                    0x65 => {
                        a = self.acc;
                        b = self.read(arg);
                    },
                    // CMP   A, !a+X      75    3     5   A - (a+X)                        N.....ZC
                    0x75 => {
                        a = self.acc;
                        b = self.read(arg +% self.x);
                    },
                    // CMP   A, !a+Y      76    3     5   A - (a+Y)                        N.....ZC
                    0x76 => {
                        a = self.acc;
                        b = self.read(arg +% self.y);
                    },
                    // CMP   X, #i        C8    2     2   X - i                            N.....ZC
                    0xC8 => {
                        a = self.x;
                        b = @intCast(arg);
                    },
                    // CMP   X, d         3E    2     3   X - (d)                          N.....ZC
                    0x3E => {
                        a = self.x;
                        b = self.read(db + arg);
                    },
                    // CMP   X, !a        1E    3     4   X - (a)                          N.....ZC
                    0x1E => {
                        a = self.x;
                        b = self.read(arg);
                    },
                    // CMP   Y, #i        AD    2     2   Y - i                            N.....ZC
                    0xAD => {
                        a = self.y;
                        b = @intCast(arg);
                    },
                    // CMP   Y, d         7E    2     3   Y - (d)                          N.....ZC
                    0x7E => {
                        a = self.y;
                        b = self.read(db + arg);
                    },
                    // CMP   Y, !a        5E    3     4   Y - (a)                          N.....ZC
                    0x5E => {
                        a = self.y;
                        b = self.read(arg);
                    },
                    // CMP   dd, ds       69    3     6   (dd) - (ds)                      N.....ZC
                    0x69 => {
                        a = self.read(db + (arg >> 8));
                        b = self.read(db + (arg & 0xff));
                    },
                    // CMP   d, #i        78    3     5   (d) - i                          N.....ZC
                    0x78 => {
                        a = self.read(db + (arg >> 8));
                        b = @intCast(arg & 0xff);
                    },
                    else => {},
                }

                const result = @subWithOverflow(a, b);
                self.psw.n = (result.@"0" & 0x80) > 0;
                self.psw.z = result.@"0" == 0;
                self.psw.c = result.@"1" == 0;
            },

            .CMPW => {
                // CMPW  YA, d        5A    2     4   YA - (d)                         N.....ZC
                const a: u16 = (@as(u16, self.y) << 8) | self.acc;
                const b = self.translateIndirect(arg8);
                const result = @subWithOverflow(a, b);
                self.psw.n = (result.@"0" & 0x8000) > 0;
                self.psw.z = result.@"0" == 0;
                self.psw.c = result.@"1" == 0;
            },

            .DAA => {
                // DAA   A            DF    1     3   decimal adjust for addition      N.....ZC
                if (self.acc > 0x99 or self.psw.c) {
                    self.acc +%= 0x60;
                    self.psw.c = true;
                }
                if ((self.acc & 0xf) > 9 or self.psw.h) {
                    self.acc +%= 0x6;
                }
                self.psw.n = (self.acc & 0x80) > 0;
                self.psw.z = self.acc == 0;
            },

            .DAS => {
                // DAS   A            BE    1     3   decimal adjust for subtraction   N.....ZC
                if (self.acc > 0x99 or !self.psw.c) {
                    self.acc -%= 0x60;
                    self.psw.c = false;
                }
                if ((self.acc & 0xf) > 9 or !self.psw.h) {
                    self.acc -%= 0x6;
                }
                self.psw.n = (self.acc & 0x80) > 0;
                self.psw.z = self.acc == 0;
            },

            .DBNZ => {
                // DBNZ  Y, r         FE    2    4/6  Y-- then JNZ                     ........
                if (code == 0xfe) {
                    self.y -%= 1;
                    if (self.y != 0) {
                        self.cycle_counter += 2;
                        self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(arg8)))));
                    }
                }
                // DBNZ  d, r         6E    3    5/7  (d)-- then JNZ                   ........
                if (code == 0x6e) {
                    var v = self.read(db + @as(u8, @intCast(arg & 0xff)));
                    v -%= 1;
                    self.write(db + @as(u8, @intCast(arg & 0xff)), v);
                    if (v != 0) {
                        self.cycle_counter += 2;
                        self.pc = @truncate(@as(u32, @bitCast(@as(i32, self.pc) + @as(i8, @bitCast(@as(u8, @intCast(arg >> 8)))))));
                    }
                }
            },

            .DEC => {
                switch (code) {
                    // DEC   A            9C    1     2   A--                              N.....Z.
                    0x9C => {
                        self.acc -%= 1;
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // DEC   X            1D    1     2   X--                              N.....Z.
                    0x1D => {
                        self.x -%= 1;
                        self.psw.n = (self.x & 0x80) > 0;
                        self.psw.z = self.x == 0;
                    },
                    // DEC   Y            DC    1     2   Y--                              N.....Z.
                    0xDC => {
                        self.y -%= 1;
                        self.psw.n = (self.y & 0x80) > 0;
                        self.psw.z = self.y == 0;
                    },
                    // DEC   d            8B    2     4   (d)--                            N.....Z.
                    0x8B => {
                        var v = self.read(db + arg);
                        v -%= 1;
                        self.write(db + arg, v);
                        self.psw.n = (v & 0x80) > 0;
                        self.psw.z = v == 0;
                    },
                    // DEC   d+X          9B    2     5   (d+X)--                          N.....Z.
                    0x9B => {
                        var v = self.read(db + @as(u16, arg8 +% self.x));
                        v -%= 1;
                        self.write(db + @as(u16, arg8 +% self.x), v);
                        self.psw.n = (v & 0x80) > 0;
                        self.psw.z = v == 0;
                    },
                    // DEC   !a           8C    3     5   (a)--                            N.....Z.
                    0x8C => {
                        var v = self.read(arg);
                        v -%= 1;
                        self.write(arg, v);
                        self.psw.n = (v & 0x80) > 0;
                        self.psw.z = v == 0;
                    },
                    else => {},
                }
            },

            .DECW => {
                // DECW  d            1A    2     6   Word (d)--                       N.....Z.
                var v: u16 = (@as(u16, self.read(db | @as(u16, arg8 +% 1)))) << 8 | self.read(db | arg8);
                v -%= 1;
                self.write(db | arg8, @intCast(v & 0xff));
                self.write(db | @as(u16, arg8 +% 1), @intCast(v >> 8));
                self.psw.n = (v & 0x8000) > 0;
                self.psw.z = v == 0;
            },

            .DI => {
                // DI                 C0    1     3   I = 0                            .....0..
                self.psw.i = false;
            },

            .EI => {
                // EI                 A0    1     3   I = 1                            .....1..
                self.psw.i = true;
            },

            .DIV => {
                // DIV   YA, X        9E    1    12   A=YA/X, Y=mod(YA,X)              NV..H.Z.
                self.psw.h = (self.x & 0xf) <= (self.y & 0xf);
                var yva: u17 = (@as(u17, self.y) << 8) | self.acc;
                const x: u17 = @as(u17, self.x) << 9;
                for (0..9) |_| {
                    yva = std.math.rotl(u17, yva, 1);
                    if (yva >= x) yva ^= 1;
                    if ((yva & 1) > 0) yva -%= x;
                }
                self.acc = @intCast(yva & 0xff);
                self.y = @intCast(yva >> 9);
                self.psw.v = ((yva >> 8) & 1) > 0;
                self.psw.n = (self.acc & 0x80) > 0;
                self.psw.z = self.acc == 0;
            },

            .EOR => {
                var a: u8 = 0;
                var b: u8 = 0;
                var result: u8 = 0;
                switch (code) {
                    // EOR   (X), (Y)     59    1     5   (X) = (X) EOR (Y)                N.....Z.
                    0x59 => {
                        a = self.read(db + self.x);
                        b = self.read(db + self.y);
                        result = a ^ b;
                        self.write(db + self.x, result);
                    },
                    // EOR   A, #i        48    2     2   A = A EOR i                      N.....Z.
                    0x48 => {
                        a = self.acc;
                        b = @intCast(arg);
                        result = a ^ b;
                        self.acc = result;
                    },
                    // EOR   A, (X)       46    1     3   A = A EOR (X)                    N.....Z.
                    0x46 => {
                        a = self.acc;
                        b = self.read(db + self.x);
                        result = a ^ b;
                        self.acc = result;
                    },
                    // EOR   A, [d]+Y     57    2     6   A = A EOR ([d]+Y)                N.....Z.
                    0x57 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8) +% self.y);
                        result = a ^ b;
                        self.acc = result;
                    },
                    // EOR   A, [d+X]     47    2     6   A = A EOR ([d+X])                N.....Z.
                    0x47 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8 +% self.x));
                        result = a ^ b;
                        self.acc = result;
                    },
                    // EOR   A, d         44    2     3   A = A EOR (d)                    N.....Z.
                    0x44 => {
                        a = self.acc;
                        b = self.read(db + arg);
                        result = a ^ b;
                        self.acc = result;
                    },
                    // EOR   A, d+X       54    2     4   A = A EOR (d+X)                  N.....Z.
                    0x54 => {
                        a = self.acc;
                        b = self.read(db + @as(u16, arg8 +% self.x));
                        result = a ^ b;
                        self.acc = result;
                    },
                    // EOR   A, !a        45    3     4   A = A EOR (a)                    N.....Z.
                    0x45 => {
                        a = self.acc;
                        b = self.read(arg);
                        result = a ^ b;
                        self.acc = result;
                    },
                    // EOR   A, !a+X      55    3     5   A = A EOR (a+X)                  N.....Z.
                    0x55 => {
                        a = self.acc;
                        b = self.read(arg +% @as(u16, self.x));
                        result = a ^ b;
                        self.acc = result;
                    },
                    // EOR   A, !a+Y      56    3     5   A = A EOR (a+Y)                  N.....Z.
                    0x56 => {
                        a = self.acc;
                        b = self.read(arg +% @as(u16, self.y));
                        result = a ^ b;
                        self.acc = result;
                    },
                    // EOR   dd, ds       49    3     6   (dd) = (dd) EOR (ds)             N.....Z.
                    0x49 => {
                        a = self.read(db + (arg >> 8));
                        b = self.read(db + (arg & 0xff));
                        result = a ^ b;
                        self.write(db + (arg >> 8), result);
                    },
                    // EOR   d, #i        58    3     5   (d) = (d) EOR i                  N.....Z.
                    0x58 => {
                        a = self.read(db + (arg >> 8));
                        b = @intCast(arg & 0xff);
                        result = a ^ b;
                        self.write(db + (arg >> 8), result);
                    },
                    else => {},
                }
                self.psw.n = (result & 0x80) > 0;
                self.psw.z = result == 0;
            },

            .EOR1 => {
                // EOR1  C, m.b       8A    3     5   C = C EOR (m.b)                  .......C
                const b: u3 = @intCast(arg >> 13);
                var v = self.read(arg & 0x1fff);
                v &= switch (b) {
                    0 => 0x01,
                    1 => 0x02,
                    2 => 0x04,
                    3 => 0x08,
                    4 => 0x10,
                    5 => 0x20,
                    6 => 0x40,
                    7 => 0x80,
                };

                self.psw.c = (@as(u1, if (self.psw.c) 1 else 0) ^ @as(u1, if (v > 0) 1 else 0)) == 1;
            },

            .INC => {
                switch (code) {
                    // INC   A            BC    1     2   A++                              N.....Z.
                    0xBC => {
                        self.acc +%= 1;
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // INC   X            3D    1     2   X++                              N.....Z.
                    0x3D => {
                        self.x +%= 1;
                        self.psw.n = (self.x & 0x80) > 0;
                        self.psw.z = self.x == 0;
                    },
                    // INC   Y            FC    1     2   Y++                              N.....Z.
                    0xFC => {
                        self.y +%= 1;
                        self.psw.n = (self.y & 0x80) > 0;
                        self.psw.z = self.y == 0;
                    },
                    // INC   d            AB    2     4   (d)++                            N.....Z.
                    0xAB => {
                        var v = self.read(db + arg);
                        v +%= 1;
                        self.write(db + arg, v);
                        self.psw.n = (v & 0x80) > 0;
                        self.psw.z = v == 0;
                    },
                    // INC   d+X          BB    2     5   (d+X)++                          N.....Z.
                    0xBB => {
                        var v = self.read(db + @as(u16, arg8 +% self.x));
                        v +%= 1;
                        self.write(db + @as(u16, arg8 +% self.x), v);
                        self.psw.n = (v & 0x80) > 0;
                        self.psw.z = v == 0;
                    },
                    // INC   !a           AC    3     5   (a)++                            N.....Z.
                    0xAC => {
                        var v = self.read(arg);
                        v +%= 1;
                        self.write(arg, v);
                        self.psw.n = (v & 0x80) > 0;
                        self.psw.z = v == 0;
                    },
                    else => {},
                }
            },

            .INCW => {
                // INCW  d            3A    2     6   Word (d)++                       N.....Z.
                var v: u16 = (@as(u16, self.read(db | @as(u16, arg8 +% 1)))) << 8 | self.read(db | arg8);
                v +%= 1;
                self.write(db | arg8, @intCast(v & 0xff));
                self.write(db | @as(u16, arg8 +% 1), @intCast(v >> 8));
                self.psw.n = (v & 0x8000) > 0;
                self.psw.z = v == 0;
            },

            .JMP => {
                // JMP   [!a+X]       1F    3     6   PC = [a+X]                       ........
                if (code == 0x1f) {
                    self.pc = @as(u16, self.read(arg +% self.x +% 1)) << 8 | self.read(arg +% self.x);
                }

                // JMP   !a           5F    3     3   PC = a                           ........
                if (code == 0x5f) {
                    self.pc = arg;
                }
            },

            .LSR => {
                var v: u8 = 0;
                switch (code) {
                    // LSR   A            5C    1     2   Right shift A: 0->high, low->C   N.....ZC
                    0x5C => {
                        self.psw.c = (self.acc & 1) > 0;
                        self.acc >>= 1;
                        v = self.acc;
                    },
                    // LSR   d            4B    2     4   Right shift (d) as above         N.....ZC
                    0x4B => {
                        v = self.read(db + arg);
                        self.psw.c = (v & 1) > 0;
                        v >>= 1;
                        self.write(db + arg, v);
                    },
                    // LSR   d+X          5B    2     5   Right shift (d+X) as above       N.....ZC
                    0x5B => {
                        v = self.read(db + @as(u16, arg8 +% self.x));
                        self.psw.c = (v & 1) > 0;
                        v >>= 1;
                        self.write(db + @as(u16, arg8 +% self.x), v);
                    },
                    // LSR   !a           4C    3     5   Right shift (a) as above         N.....ZC
                    0x4C => {
                        v = self.read(arg);
                        self.psw.c = (v & 1) > 0;
                        v >>= 1;
                        self.write(arg, v);
                    },
                    else => {},
                }
                self.psw.n = (v & 0x80) > 0;
                self.psw.z = v == 0;
            },

            .MOV => {
                switch (code) {
                    // MOV   (X)+, A      AF    1     4   (X++) = A      (no read)         ........
                    0xAF => {
                        self.write(db + self.x, self.acc);
                        self.x +%= 1;
                    },
                    // MOV   (X), A       C6    1     4   (X) = A        (read)            ........
                    0xC6 => {
                        _ = self.read(db + self.x);
                        self.write(db + self.x, self.acc);
                    },
                    // MOV   [d]+Y, A     D7    2     7   ([d]+Y) = A    (read)            ........
                    0xD7 => {
                        const a = self.translateIndirect(arg8) +% self.y;
                        _ = self.read(a);
                        self.write(a, self.acc);
                    },
                    // MOV   [d+X], A     C7    2     7   ([d+X]) = A    (read)            ........
                    0xC7 => {
                        const a = self.translateIndirect(arg8 +% self.x);
                        _ = self.read(a);
                        self.write(a, self.acc);
                    },
                    // MOV   A, #i        E8    2     2   A = i                            N.....Z.
                    0xE8 => {
                        self.acc = @intCast(arg);
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   A, (X)       E6    1     3   A = (X)                          N.....Z.
                    0xE6 => {
                        self.acc = self.read(db + self.x);
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   A, (X)+      BF    1     4   A = (X++)                        N.....Z.
                    0xBF => {
                        self.acc = self.read(db + self.x);
                        self.x +%= 1;
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   A, [d]+Y     F7    2     6   A = ([d]+Y)                      N.....Z.
                    0xF7 => {
                        self.acc = self.read(self.translateIndirect(arg8) +% self.y);
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   A, [d+X]     E7    2     6   A = ([d+X])                      N.....Z.
                    0xE7 => {
                        self.acc = self.read(self.translateIndirect(arg8 +% self.x));
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   A, X         7D    1     2   A = X                            N.....Z.
                    0x7D => {
                        self.acc = self.x;
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   A, Y         DD    1     2   A = Y                            N.....Z.
                    0xDD => {
                        self.acc = self.y;
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   A, d         E4    2     3   A = (d)                          N.....Z.
                    0xE4 => {
                        self.acc = self.read(db + arg);
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   A, d+X       F4    2     4   A = (d+X)                        N.....Z.
                    0xF4 => {
                        self.acc = self.read(db + @as(u16, arg8 +% self.x));
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   A, !a        E5    3     4   A = (a)                          N.....Z.
                    0xE5 => {
                        self.acc = self.read(arg);
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   A, !a+X      F5    3     5   A = (a+X)                        N.....Z.
                    0xF5 => {
                        self.acc = self.read(arg +% self.x);
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   A, !a+Y      F6    3     5   A = (a+Y)                        N.....Z.
                    0xF6 => {
                        self.acc = self.read(arg +% self.y);
                        self.psw.n = (self.acc & 0x80) > 0;
                        self.psw.z = self.acc == 0;
                    },
                    // MOV   SP, X        BD    1     2   SP = X                           ........
                    0xBD => {
                        self.sp = self.x;
                    },
                    // MOV   X, #i        CD    2     2   X = i                            N.....Z.
                    0xCD => {
                        self.x = @intCast(arg);
                        self.psw.n = (self.x & 0x80) > 0;
                        self.psw.z = self.x == 0;
                    },
                    // MOV   X, A         5D    1     2   X = A                            N.....Z.
                    0x5D => {
                        self.x = self.acc;
                        self.psw.n = (self.x & 0x80) > 0;
                        self.psw.z = self.x == 0;
                    },
                    // MOV   X, SP        9D    1     2   X = SP                           N.....Z.
                    0x9D => {
                        self.x = self.sp;
                        self.psw.n = (self.x & 0x80) > 0;
                        self.psw.z = self.x == 0;
                    },
                    // MOV   X, d         F8    2     3   X = (d)                          N.....Z.
                    0xF8 => {
                        self.x = self.read(db + arg);
                        self.psw.n = (self.x & 0x80) > 0;
                        self.psw.z = self.x == 0;
                    },
                    // MOV   X, d+Y       F9    2     4   X = (d+Y)                        N.....Z.
                    0xF9 => {
                        self.x = self.read(db + @as(u16, arg8 +% self.y));
                        self.psw.n = (self.x & 0x80) > 0;
                        self.psw.z = self.x == 0;
                    },
                    // MOV   X, !a        E9    3     4   X = (a)                          N.....Z.
                    0xE9 => {
                        self.x = self.read(arg);
                        self.psw.n = (self.x & 0x80) > 0;
                        self.psw.z = self.x == 0;
                    },
                    // MOV   Y, #i        8D    2     2   Y = i                            N.....Z.
                    0x8D => {
                        self.y = @intCast(arg);
                        self.psw.n = (self.y & 0x80) > 0;
                        self.psw.z = self.y == 0;
                    },
                    // MOV   Y, A         FD    1     2   Y = A                            N.....Z.
                    0xFD => {
                        self.y = self.acc;
                        self.psw.n = (self.y & 0x80) > 0;
                        self.psw.z = self.y == 0;
                    },
                    // MOV   Y, d         EB    2     3   Y = (d)                          N.....Z.
                    0xEB => {
                        self.y = self.read(db + arg);
                        self.psw.n = (self.y & 0x80) > 0;
                        self.psw.z = self.y == 0;
                    },
                    // MOV   Y, d+X       FB    2     4   Y = (d+X)                        N.....Z.
                    0xFB => {
                        self.y = self.read(db + @as(u16, arg8 +% self.x));
                        self.psw.n = (self.y & 0x80) > 0;
                        self.psw.z = self.y == 0;
                    },
                    // MOV   Y, !a        EC    3     4   Y = (a)                          N.....Z.
                    0xEC => {
                        self.y = self.read(arg);
                        self.psw.n = (self.y & 0x80) > 0;
                        self.psw.z = self.y == 0;
                    },
                    // MOV   dd, ds       FA    3     5   (dd) = (ds)    (no read)         ........
                    0xFA => {
                        self.write(db + (arg >> 8), self.read(db + (arg & 0xff)));
                    },
                    // MOV   d+X, A       D4    2     5   (d+X) = A      (read)            ........
                    0xD4 => {
                        const v: u16 = db + @as(u16, arg8 +% self.x);
                        _ = self.read(v);
                        self.write(v, self.acc);
                    },
                    // MOV   d+X, Y       DB    2     5   (d+X) = Y      (read)            ........
                    0xDB => {
                        const v: u16 = db + @as(u16, arg8 +% self.x);
                        _ = self.read(v);
                        self.write(v, self.y);
                    },
                    // MOV   d+Y, X       D9    2     5   (d+Y) = X      (read)            ........
                    0xD9 => {
                        const v: u16 = db + @as(u16, arg8 +% self.y);
                        _ = self.read(v);
                        self.write(v, self.x);
                    },
                    // MOV   d, #i        8F    3     5   (d) = i        (read)            ........
                    0x8F => {
                        _ = self.read(db + (arg >> 8));
                        self.write(db + (arg >> 8), @intCast(arg & 0xff));
                    },
                    // MOV   d, A         C4    2     4   (d) = A        (read)            ........
                    0xC4 => {
                        const v: u16 = db + arg;
                        _ = self.read(v);
                        self.write(v, self.acc);
                    },
                    // MOV   d, X         D8    2     4   (d) = X        (read)            ........
                    0xD8 => {
                        const v: u16 = db + arg;
                        _ = self.read(v);
                        self.write(v, self.x);
                    },
                    // MOV   d, Y         CB    2     4   (d) = Y        (read)            ........
                    0xCB => {
                        const v: u16 = db + arg;
                        _ = self.read(v);
                        self.write(v, self.y);
                    },
                    // MOV   !a+X, A      D5    3     6   (a+X) = A      (read)            ........
                    0xD5 => {
                        const v: u16 = arg +% self.x;
                        _ = self.read(v);
                        self.write(v, self.acc);
                    },
                    // MOV   !a+Y, A      D6    3     6   (a+Y) = A      (read)            ........
                    0xD6 => {
                        const v: u16 = arg +% self.y;
                        _ = self.read(v);
                        self.write(v, self.acc);
                    },
                    // MOV   !a, A        C5    3     5   (a) = A        (read)            ........
                    0xC5 => {
                        _ = self.read(arg);
                        self.write(arg, self.acc);
                    },
                    // MOV   !a, X        C9    3     5   (a) = X        (read)            ........
                    0xC9 => {
                        _ = self.read(arg);
                        self.write(arg, self.x);
                    },
                    // MOV   !a, Y        CC    3     5   (a) = Y        (read)            ........
                    0xCC => {
                        _ = self.read(arg);
                        self.write(arg, self.y);
                    },
                    else => {},
                }
            },

            .MOV1 => {
                const b: u3 = @as(u3, @intCast(arg >> 13));
                // MOV1  C, m.b       AA    3     4   C = (m.b)                        .......C
                if (code == 0xaa) {
                    var v = self.read(arg & 0x1fff);
                    v &= switch (b) {
                        0 => 0x01,
                        1 => 0x02,
                        2 => 0x04,
                        3 => 0x08,
                        4 => 0x10,
                        5 => 0x20,
                        6 => 0x40,
                        7 => 0x80,
                    };
                    self.psw.c = v > 0;
                }

                // MOV1  m.b, C       CA    3     6   (m.b) = C                        ........
                if (code == 0xca) {
                    var v = self.read(arg & 0x1fff);
                    const cc: u8 = if (self.psw.c) 1 else 0;
                    v &= switch (b) {
                        0 => 0xfe,
                        1 => 0xfd,
                        2 => 0xfb,
                        3 => 0xf7,
                        4 => 0xef,
                        5 => 0xdf,
                        6 => 0xbf,
                        7 => 0x7f,
                    };
                    v |= cc << b;
                    self.write(arg & 0x1fff, v);
                }
            },

            .MOVW => {
                // MOVW  YA, d        BA    2     5   YA = word (d)                    N.....Z.
                if (code == 0xba) {
                    const v = self.translateIndirect(arg8);
                    self.acc = @intCast(v & 0xff);
                    self.y = @intCast(v >> 8);
                    self.psw.n = (self.y & 0x80) > 0;
                    self.psw.z = self.acc == 0 and self.y == 0;
                }

                // MOVW  d, YA        DA    2     5   word (d) = YA  (read low only)   ........
                if (code == 0xda) {
                    _ = self.read(self.acc);
                    self.write(db | arg8, self.acc);
                    self.write(db | @as(u16, arg8 +% 1), self.y);
                }
            },

            .MUL => {
                // MUL   YA           CF    1     9   YA = Y * A, NZ on Y only         N.....Z.
                const v: u16 = @as(u16, self.y) *% @as(u16, self.acc);
                self.y = @intCast(v >> 8);
                self.acc = @intCast(v & 0xff);
                self.psw.n = (self.y & 0x80) > 0;
                self.psw.z = self.y == 0;
            },

            .NOT1 => {
                // NOT1  m.b          EA    3     5   m.b = ~m.b                       ........
                var v = self.read(arg & 0x1fff);
                const b: u3 = @as(u3, @intCast(arg >> 13));
                const o = v;

                v &= switch (b) {
                    0 => 0x01,
                    1 => 0x02,
                    2 => 0x04,
                    3 => 0x08,
                    4 => 0x10,
                    5 => 0x20,
                    6 => 0x40,
                    7 => 0x80,
                };

                if (v > 0) {
                    self.write(arg & 0x1fff, o & ~v);
                } else {
                    self.write(arg & 0x1fff, o | (@as(u8, 1) << b));
                }
            },

            .NOTC => {
                // NOTC               ED    1     3   C = !C                           .......C
                self.psw.c = !self.psw.c;
            },

            .OR => {
                var a: u8 = 0;
                var b: u8 = 0;
                var result: u8 = 0;
                switch (code) {
                    // OR    (X), (Y)     19    1     5   (X) = (X) | (Y)                  N.....Z.
                    0x19 => {
                        a = self.read(db + self.x);
                        b = self.read(db + self.y);
                        result = a | b;
                        self.write(db + self.x, result);
                    },
                    // OR    A, #i        08    2     2   A = A | i                        N.....Z.
                    0x08 => {
                        a = self.acc;
                        b = @intCast(arg);
                        result = a | b;
                        self.acc = result;
                    },
                    // OR    A, (X)       06    1     3   A = A | (X)                      N.....Z.
                    0x06 => {
                        a = self.acc;
                        b = self.read(db + self.x);
                        result = a | b;
                        self.acc = result;
                    },
                    // OR    A, [d]+Y     17    2     6   A = A | ([d]+Y)                  N.....Z.
                    0x17 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8) +% self.y);
                        result = a | b;
                        self.acc = result;
                    },
                    // OR    A, [d+X]     07    2     6   A = A | ([d+X])                  N.....Z.
                    0x07 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8 +% self.x));
                        result = a | b;
                        self.acc = result;
                    },
                    // OR    A, d         04    2     3   A = A | (d)                      N.....Z.
                    0x04 => {
                        a = self.acc;
                        b = self.read(db + arg);
                        result = a | b;
                        self.acc = result;
                    },
                    // OR    A, d+X       14    2     4   A = A | (d+X)                    N.....Z.
                    0x14 => {
                        a = self.acc;
                        b = self.read(db + @as(u16, arg8 +% self.x));
                        result = a | b;
                        self.acc = result;
                    },
                    // OR    A, !a        05    3     4   A = A | (a)                      N.....Z.
                    0x05 => {
                        a = self.acc;
                        b = self.read(arg);
                        result = a | b;
                        self.acc = result;
                    },
                    // OR    A, !a+X      15    3     5   A = A | (a+X)                    N.....Z.
                    0x15 => {
                        a = self.acc;
                        b = self.read(arg +% @as(u16, self.x));
                        result = a | b;
                        self.acc = result;
                    },
                    // OR    A, !a+Y      16    3     5   A = A | (a+Y)                    N.....Z.
                    0x16 => {
                        a = self.acc;
                        b = self.read(arg +% @as(u16, self.y));
                        result = a | b;
                        self.acc = result;
                    },
                    // OR    dd, ds       09    3     6   (dd) = (dd) | (ds)               N.....Z.
                    0x09 => {
                        a = self.read(db + (arg >> 8));
                        b = self.read(db + (arg & 0xff));
                        result = a | b;
                        self.write(db + (arg >> 8), result);
                    },
                    // OR    d, #i        18    3     5   (d) = (d) | i                    N.....Z.
                    0x18 => {
                        a = self.read(db + (arg >> 8));
                        b = @intCast(arg & 0xff);
                        result = a | b;
                        self.write(db + (arg >> 8), result);
                    },
                    else => {},
                }
                self.psw.n = (result & 0x80) > 0;
                self.psw.z = result == 0;
            },

            .OR1 => {
                const b: u3 = @intCast(arg >> 13);
                var v = self.read(arg & 0x1fff);
                v &= switch (b) {
                    0 => 0x01,
                    1 => 0x02,
                    2 => 0x04,
                    3 => 0x08,
                    4 => 0x10,
                    5 => 0x20,
                    6 => 0x40,
                    7 => 0x80,
                };
                // OR1   C, /m.b      2A    3     5   C = C | ~(m.b)                   .......C
                if (code == 0x2a) {
                    self.psw.c = self.psw.c or (v == 0);
                }

                // OR1   C, m.b       0A    3     5   C = C | (m.b)                    .......C
                if (code == 0x0a) {
                    self.psw.c = self.psw.c or (v > 0);
                }
            },

            .PCALL => {
                // PCALL u            4F    2     6   CALL $FF00+u                     ........
                self.write(0x100 | @as(u16, self.sp), @intCast(self.pc >> 8));
                self.sp -%= 1;
                self.write(0x100 | @as(u16, self.sp), @intCast(self.pc & 0xff));
                self.sp -%= 1;
                self.pc = @as(u16, 0xff00) | arg;
            },

            .POP => {
                switch (code) {
                    // POP   A            AE    1     4   A = (++SP)                       ........
                    0xae => {
                        self.sp +%= 1;
                        self.acc = self.read(0x100 | @as(u16, self.sp));
                    },
                    // POP   PSW          8E    1     4   Flags = (++SP)                   NVPBHIZC
                    0x8e => {
                        self.sp +%= 1;
                        self.psw = @bitCast(self.read(0x100 | @as(u16, self.sp)));
                    },
                    // POP   X            CE    1     4   X = (++SP)                       ........
                    0xce => {
                        self.sp +%= 1;
                        self.x = self.read(0x100 | @as(u16, self.sp));
                    },
                    // POP   Y            EE    1     4   Y = (++SP)                       ........
                    0xee => {
                        self.sp +%= 1;
                        self.y = self.read(0x100 | @as(u16, self.sp));
                    },
                    else => {},
                }
            },

            .PUSH => {
                switch (code) {
                    // PUSH  A            2D    1     4   (SP--) = A                       ........
                    0x2d => {
                        self.write(0x100 | @as(u16, self.sp), self.acc);
                        self.sp -%= 1;
                    },
                    // PUSH  PSW          0D    1     4   (SP--) = Flags                   ........
                    0x0d => {
                        self.write(0x100 | @as(u16, self.sp), @bitCast(self.psw));
                        self.sp -%= 1;
                    },
                    // PUSH  X            4D    1     4   (SP--) = X                       ........
                    0x4d => {
                        self.write(0x100 | @as(u16, self.sp), self.x);
                        self.sp -%= 1;
                    },
                    // PUSH  Y            6D    1     4   (SP--) = Y                       ........
                    0x6d => {
                        self.write(0x100 | @as(u16, self.sp), self.y);
                        self.sp -%= 1;
                    },
                    else => {},
                }
            },

            .RET => {
                // RET                6F    1     5   Pop PC                           ........
                self.sp +%= 1;
                self.pc = self.read(0x100 | @as(u16, self.sp));
                self.sp +%= 1;
                self.pc |= @as(u16, self.read(0x100 | @as(u16, self.sp))) << 8;
            },

            .RET1 => {
                // RET1               7F    1     6   Pop Flags, PC                    NVPBHIZC
                self.sp +%= 1;
                self.psw = @bitCast(self.read(0x100 | @as(u16, self.sp)));
                self.sp +%= 1;
                self.pc = self.read(0x100 | @as(u16, self.sp));
                self.sp +%= 1;
                self.pc |= @as(u16, self.read(0x100 | @as(u16, self.sp))) << 8;
            },

            .ROL => {
                var v: u8 = 0;
                const cc: u8 = if (self.psw.c) 1 else 0;
                switch (code) {
                    // ROL   A            3C    1     2   Left shift A: low=C, C=high      N.....ZC
                    0x3C => {
                        self.psw.c = (self.acc & 0x80) > 0;
                        self.acc <<= 1;
                        self.acc |= cc;
                        v = self.acc;
                    },
                    // ROL   d            2B    2     4   Left shift (d) as above          N.....ZC
                    0x2B => {
                        v = self.read(db + arg);
                        self.psw.c = (v & 0x80) > 0;
                        v <<= 1;
                        v |= cc;
                        self.write(db + arg, v);
                    },
                    // ROL   d+X          3B    2     5   Left shift (d+X) as above        N.....ZC
                    0x3B => {
                        v = self.read(db + @as(u16, arg8 +% self.x));
                        self.psw.c = (v & 0x80) > 0;
                        v <<= 1;
                        v |= cc;
                        self.write(db + @as(u16, arg8 +% self.x), v);
                    },
                    // ROL   !a           2C    3     5   Left shift (a) as above          N.....ZC
                    0x2C => {
                        v = self.read(arg);
                        self.psw.c = (v & 0x80) > 0;
                        v <<= 1;
                        v |= cc;
                        self.write(arg, v);
                    },
                    else => {},
                }
                self.psw.n = (v & 0x80) > 0;
                self.psw.z = v == 0;
            },

            .ROR => {
                var v: u8 = 0;
                const cc: u8 = if (self.psw.c) 0x80 else 0;
                switch (code) {
                    // ROR   A            7C    1     2   Right shift A: high=C, C=low     N.....ZC
                    0x7C => {
                        self.psw.c = (self.acc & 1) > 0;
                        self.acc >>= 1;
                        self.acc |= cc;
                        v = self.acc;
                    },
                    // ROR   d            6B    2     4   Right shift (d) as above         N.....ZC
                    0x6B => {
                        v = self.read(db + arg);
                        self.psw.c = (v & 1) > 0;
                        v >>= 1;
                        v |= cc;
                        self.write(db + arg, v);
                    },
                    // ROR   d+X          7B    2     5   Right shift (d+X) as above       N.....ZC
                    0x7B => {
                        v = self.read(db + @as(u16, arg8 +% self.x));
                        self.psw.c = (v & 1) > 0;
                        v >>= 1;
                        v |= cc;
                        self.write(db + @as(u16, arg8 +% self.x), v);
                    },
                    // ROR   !a           6C    3     5   Right shift (a) as above         N.....ZC
                    0x6C => {
                        v = self.read(arg);
                        self.psw.c = (v & 1) > 0;
                        v >>= 1;
                        v |= cc;
                        self.write(arg, v);
                    },
                    else => {},
                }
                self.psw.n = (v & 0x80) > 0;
                self.psw.z = v == 0;
            },

            .SBC => {
                var a: u8 = 0;
                var b: u8 = 0;
                const cc: u8 = if (self.psw.c) 0 else 1;
                var result: u8 = 0;
                var carried = false;
                switch (code) {
                    // SBC   (X), (Y)     B9    1     5   (X) = (X)-(Y)-!C                 NV..H.ZC
                    0xb9 => {
                        a = self.read(db + self.x);
                        b = self.read(db + self.y);
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.write(db + self.x, result);
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    // SBC   A, #i        A8    2     2   A = A-i-!C                       NV..H.ZC
                    0xa8 => {
                        a = self.acc;
                        b = @intCast(arg);
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.acc = result;
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    // SBC   A, (X)       A6    1     3   A = A-(X)-!C                     NV..H.ZC
                    0xa6 => {
                        a = self.acc;
                        b = self.read(db + self.x);
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.acc = result;
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    // SBC   A, [d]+Y     B7    2     6   A = A-([d]+Y)-!C                 NV..H.ZC
                    0xb7 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8) +% self.y);
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.acc = result;
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    // SBC   A, [d+X]     A7    2     6   A = A-([d+X])-!C                 NV..H.ZC
                    0xa7 => {
                        a = self.acc;
                        b = self.read(self.translateIndirect(arg8 +% self.x));
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.acc = result;
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    // SBC   A, d         A4    2     3   A = A-(d)-!C                     NV..H.ZC
                    0xa4 => {
                        a = self.acc;
                        b = self.read(db + arg);
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.acc = result;
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    // SBC   A, d+X       B4    2     4   A = A-(d+X)-!C                   NV..H.ZC
                    0xb4 => {
                        a = self.acc;
                        b = self.read(db + @as(u16, arg8 +% self.x));
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.acc = result;
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    // SBC   A, !a        A5    3     4   A = A-(a)-!C                     NV..H.ZC
                    0xa5 => {
                        a = self.acc;
                        b = self.read(arg);
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.acc = result;
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    // SBC   A, !a+X      B5    3     5   A = A-(a+X)-!C                   NV..H.ZC
                    0xb5 => {
                        a = self.acc;
                        b = self.read(arg +% self.x);
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.acc = result;
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    // SBC   A, !a+Y      B6    3     5   A = A-(a+Y)-!C                   NV..H.ZC
                    0xb6 => {
                        a = self.acc;
                        b = self.read(arg +% self.y);
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.acc = result;
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    // SBC   dd, ds       A9    3     6   (dd) = (dd)-(ds)-!C              NV..H.ZC
                    0xa9 => {
                        a = self.read(db + (arg >> 8));
                        b = self.read(db + (arg & 0xff));
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.write(db + (arg >> 8), result);
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    // SBC   d, #i        B8    3     5   (d) = (d)-i-!C                   NV..H.ZC
                    0xb8 => {
                        a = self.read(db + (arg >> 8));
                        b = @intCast(arg & 0xff);
                        const sub1 = @subWithOverflow(a, b);
                        const sub2 = @subWithOverflow(sub1.@"0", cc);
                        result = sub2.@"0";
                        self.write(db + (arg >> 8), result);
                        carried = sub1.@"1" == 0 and sub2.@"1" == 0;
                    },
                    else => {},
                }
                self.psw.z = result == 0;
                self.psw.n = (result & 0x80) > 0;
                self.psw.c = carried;
                self.psw.v = ((a ^ result) & ((255 - b) ^ result) & 0x80) > 0;
                self.psw.h = (a ^ b ^ cc ^ result) & 0x10 == 0;
            },

            .SET1 => {
                // SET1  d.n          02    2     4   d.n = 1                          ........
                var v = self.read(db + arg);
                v |= switch (code) {
                    0x02 => 0x01,
                    0x22 => 0x02,
                    0x42 => 0x04,
                    0x62 => 0x08,
                    0x82 => 0x10,
                    0xA2 => 0x20,
                    0xC2 => 0x40,
                    0xE2 => 0x80,
                    else => 0,
                };
                self.write(db + arg, v);
            },

            .SETC => {
                // SETC               80    1     2   C = 1                            .......1
                self.psw.c = true;
            },

            .SETP => {
                // SETP               40    1     2   P = 1                            ..1.....
                self.psw.p = true;
            },

            .SUBW => {
                // SUBW  YA, d        9A    2     5   YA  = YA - (d), H on high byte   NV..H.ZC
                const a = (@as(u16, self.y) << 8) | self.acc;
                const b = self.translateIndirect(arg8);
                const sub = @subWithOverflow(a, b);
                const result = sub.@"0";
                self.y = @intCast(result >> 8);
                self.acc = @intCast(result & 0xff);
                self.psw.z = result == 0;
                self.psw.n = (result & 0x8000) > 0;
                self.psw.c = sub.@"1" == 0;
                self.psw.v = ((a ^ result) & ((65535 - b) ^ result) & 0x8000) > 0;
                self.psw.h = (a ^ b ^ result) & 0x1000 == 0;
            },

            .TCALL => {
                // TCALL n            01    1     8   CALL [$FFhh], hh = $DE-n*2       ........
                self.write(0x100 | @as(u16, self.sp), @intCast(self.pc >> 8));
                self.sp -%= 1;
                self.write(0x100 | @as(u16, self.sp), @intCast(self.pc & 0xff));
                self.sp -%= 1;
                const v = @as(u16, 0xffde) - ((code & 0xf0) >> 4) * 2;
                self.pc = @as(u16, self.read(v + 1)) << 8 | self.read(v);
            },

            .TCLR1 => {
                // TCLR1 !a           4E    3     6   (a) = (a)&~A, ZN as for A-(a)    N.....Z.
                const a = self.read(arg);
                const v = self.acc -% a;
                self.write(arg, a & ~self.acc);
                self.psw.n = (v & 0x80) > 0;
                self.psw.z = v == 0;
            },

            .TSET1 => {
                // TSET1 !a           0E    3     6   (a) = (a)|A, ZN as for A-(a)     N.....Z.
                const a = self.read(arg);
                const v = self.acc -% a;
                self.write(arg, a | self.acc);
                self.psw.n = (v & 0x80) > 0;
                self.psw.z = v == 0;
            },

            .XCN => {
                // XCN   A            9F    1     5   A = (A>>4) | (A<<4)              N.....Z.
                const a = self.acc;
                self.acc = (a >> 4) | (a << 4);
                self.psw.n = (self.acc & 0x80) > 0;
                self.psw.z = self.acc == 0;
            },

            .SLEEP => self.halt = true,
            .STOP => self.halt = true,
            .NOP => {},
        }
    }

    pub fn reset(self: *APU) void {
        self.dsp.reset();
        self.timer0.output = 0xf;
        self.timer1.output = 0xf;
        self.timer2.output = 0xf;
        @memset(self.ram, 0);
        self.write(0xf1, 0xb0);
        self.write(0xf2, 0xff);
        self.ram[0xf0] = 0x0a;
        self.ram[0xf8] = 0xff;
        self.ram[0xf9] = 0xff;
        self.ram[0xfa] = 0xff;
        self.ram[0xfb] = 0xff;
        self.ram[0xfc] = 0xff;
        self.ram[0xfd] = 0;
        self.ram[0xfe] = 0;
        self.ram[0xff] = 0;
        self.pc = 0xffc0;
        self.sp = 0xff;
        self.acc = 0;
        self.x = 0;
        self.y = 0;
        self.psw = @bitCast(@as(u8, 0));
        self.halt = false;
        self.cycle_counter = 0;
    }

    pub fn serialize(self: *const APU, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "ram");
        c.mpack_start_bin(pack, @intCast(self.ram.len));
        c.mpack_write_bytes(pack, self.ram.ptr, self.ram.len);
        c.mpack_finish_bin(pack);

        c.mpack_write_cstr(pack, "dsp");
        self.dsp.serialize(pack);

        c.mpack_write_cstr(pack, "timer0");
        self.timer0.serialize(pack);

        c.mpack_write_cstr(pack, "timer1");
        self.timer1.serialize(pack);

        c.mpack_write_cstr(pack, "timer2");
        self.timer2.serialize(pack);

        c.mpack_write_cstr(pack, "apuio0");
        c.mpack_write_u8(pack, self.apuio0);
        c.mpack_write_cstr(pack, "apuio1");
        c.mpack_write_u8(pack, self.apuio1);
        c.mpack_write_cstr(pack, "apuio2");
        c.mpack_write_u8(pack, self.apuio2);
        c.mpack_write_cstr(pack, "apuio3");
        c.mpack_write_u8(pack, self.apuio3);
        c.mpack_write_cstr(pack, "pc");
        c.mpack_write_u16(pack, self.pc);
        c.mpack_write_cstr(pack, "sp");
        c.mpack_write_u8(pack, self.sp);
        c.mpack_write_cstr(pack, "acc");
        c.mpack_write_u8(pack, self.acc);
        c.mpack_write_cstr(pack, "x");
        c.mpack_write_u8(pack, self.x);
        c.mpack_write_cstr(pack, "y");
        c.mpack_write_u8(pack, self.y);
        c.mpack_write_cstr(pack, "psw");
        c.mpack_write_u8(pack, @bitCast(self.psw));
        c.mpack_write_cstr(pack, "halt");
        c.mpack_write_bool(pack, self.halt);
        c.mpack_write_cstr(pack, "cycle_counter");
        c.mpack_write_u32(pack, self.cycle_counter);
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *APU, pack: c.mpack_node_t) void {
        @memset(self.ram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "ram"), self.ram.ptr, self.ram.len);

        self.dsp.deserialize(c.mpack_node_map_cstr(pack, "dsp"));
        self.timer0.deserialize(c.mpack_node_map_cstr(pack, "timer0"));
        self.timer1.deserialize(c.mpack_node_map_cstr(pack, "timer1"));
        self.timer2.deserialize(c.mpack_node_map_cstr(pack, "timer2"));

        self.apuio0 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "apuio0"));
        self.apuio1 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "apuio1"));
        self.apuio2 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "apuio2"));
        self.apuio3 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "apuio3"));
        self.pc = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "pc"));
        self.sp = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "sp"));
        self.acc = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "acc"));
        self.x = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "x"));
        self.y = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "y"));
        self.psw = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "psw")));
        self.halt = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "halt"));
        self.cycle_counter = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "cycle_counter"));
    }

    pub fn memory(self: *@This()) Memory(u24, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = mmio_read,
                .write = mmio_write,
                .deinit = deinitMemory,
            },
        };
    }
};

const PSW = packed struct {
    c: bool,
    z: bool,
    i: bool,
    h: bool,
    b: bool,
    p: bool,
    v: bool,
    n: bool,
};

const BOOT_ROM: [64]u8 = [64]u8{
    0xCD, 0xEF, 0xBD, 0xE8, 0x00, 0xC6, 0x1D, 0xD0, 0xFC, 0x8F, 0xAA, 0xF4, 0x8F, 0xBB, 0xF5, 0x78, //
    0xCC, 0xF4, 0xD0, 0xFB, 0x2F, 0x19, 0xEB, 0xF4, 0xD0, 0xFC, 0x7E, 0xF4, 0xD0, 0x0B, 0xE4, 0xF5, //
    0xCB, 0xF4, 0xD7, 0x00, 0xFC, 0xD0, 0xF3, 0xAB, 0x01, 0x10, 0xEF, 0x7E, 0xF4, 0x10, 0xEB, 0xBA, //
    0xF6, 0xDA, 0x00, 0xBA, 0xF4, 0xC4, 0xF4, 0xDD, 0x5D, 0xD0, 0xDB, 0x1F, 0x00, 0x00, 0xC0, 0xFF, //
};
