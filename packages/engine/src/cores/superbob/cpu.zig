const std = @import("std");
const c = @import("../../c.zig");
const opcode = @import("opcode.zig");
const Memory = @import("../../memory.zig").Memory;

const CPUState = enum { normal, wait, stop };
pub const IRQType = enum { cop, abort, nmi, reset, irq };

pub const CPU = struct {
    cycle_counter: u32 = 0,
    state: CPUState = .normal,
    memsel: *bool = undefined,
    halt: bool = false,

    irq_requested: bool = false,
    nmi_requested: bool = false,
    nmi_occurred: bool = false,

    resolved_address: u24 = 0,
    resolved_mask: u24 = 0,

    pc_s: packed union {
        pc: u16,
        hl: packed struct {
            pcl: u8,
            pch: u8,
        },
    } = @bitCast(@as(u16, 0)),

    sp_s: packed union {
        s: u16,
        hl: packed struct {
            sl: u8,
            sh: u8,
        },
    } = @bitCast(@as(u16, 0x1ff)),

    a_s: packed union {
        c: u16,
        hl: packed struct {
            a: u8,
            b: u8,
        },
    } = @bitCast(@as(u16, 0)),

    x_s: packed union {
        x: u16,
        hl: packed struct {
            xl: u8,
            xh: u8,
        },
    } = @bitCast(@as(u16, 0)),

    y_s: packed union {
        y: u16,
        hl: packed struct {
            yl: u8,
            yh: u8,
        },
    } = @bitCast(@as(u16, 0)),

    d_s: packed union {
        d: u16,
        hl: packed struct {
            dl: u8,
            dh: u8,
        },
    } = @bitCast(@as(u16, 0)),

    db: u8 = 0,
    pb: u8 = 0,

    e: bool = true,
    p: packed struct {
        c: bool,
        z: bool,
        i: bool,
        d: bool,
        x: bool,
        m: bool,
        v: bool,
        n: bool,
    } = @bitCast(@as(u8, 0x30)),

    memory: Memory(u24, u8),

    pub fn memoryCycles(self: *CPU, address: u24) u8 {
        const bank: u8 = @intCast(address >> 16);
        const page: u8 = @intCast((address & 0xff00) >> 8);
        return switch (bank) {
            0x00...0x3f => switch (page) {
                0x00...0x1f => 8,
                0x20...0x3f => 6,
                0x40...0x41 => 12,
                0x42...0x5f => 6,
                0x60...0xff => 8,
            },
            0x40...0x7f => 8,
            0x80...0xbf => switch (page) {
                0x00...0x1f => 8,
                0x20...0x3f => 6,
                0x40...0x41 => 12,
                0x42...0x5f => 6,
                0x60...0x7f => 8,
                0x80...0xff => if (self.memsel.*) 6 else 8,
            },
            0xc0...0xff => if (self.memsel.*) 6 else 8,
        };
    }

    inline fn read(self: *CPU, address: u24) u8 {
        self.cycle_counter += self.memoryCycles(address);
        return self.memory.read(address);
    }

    inline fn write(self: *CPU, address: u24, value: u8) void {
        self.cycle_counter += self.memoryCycles(address);
        self.memory.write(address, value);
    }

    fn push(self: *CPU, value: u8) void {
        if (self.e) {
            const addr = 0x100 | @as(u16, self.sp_s.hl.sl);
            self.write(addr, value);
            self.sp_s.hl.sl -%= 1;
        } else {
            self.write(self.sp_s.s, value);
            self.sp_s.s -%= 1;
        }
    }

    fn pop(self: *CPU) u8 {
        if (self.e) {
            self.sp_s.hl.sl +%= 1;
            const addr = 0x100 | @as(u16, self.sp_s.hl.sl);
            return self.read(addr);
        } else {
            self.sp_s.s +%= 1;
            return self.read(self.sp_s.s);
        }
    }

    fn checkPageCrossing(address: u24, offset: u16) bool {
        return (address & 0xff00) != ((address +% offset) & 0xff00);
    }

    fn nextResolvedAddress(self: *CPU) u24 {
        const m = self.resolved_address & ~self.resolved_mask;
        if (self.e and self.d_s.hl.dl == 0) {
            const v = ((self.resolved_address & 0xffff00) | ((self.resolved_address +% 1) & 0xff)) & self.resolved_mask;
            self.resolved_address = m | v;
        } else {
            const v = (self.resolved_address +% 1) & self.resolved_mask;
            self.resolved_address = m | v;
        }
        return self.resolved_address;
    }

    fn resolveAddress(self: *CPU, op: opcode.Opcode, address: u24) bool {
        var page_crossed = false;

        switch (op.mode) {
            .imp, .acc => {},
            .imm, .mov => self.resolved_address = address,

            .zpg => {
                if (self.d_s.hl.dl != 0) self.cycle_counter += 6;
                if (op.instruction != .PEI and self.e and self.d_s.hl.dl == 0) {
                    self.resolved_address = (@as(u16, self.d_s.hl.dh) << 8) | address;
                } else {
                    self.resolved_address = (address +% self.d_s.d) & 0xffff;
                }
                self.resolved_mask = 0x00ffff;
            },

            .zpx => {
                if (self.d_s.hl.dl != 0) self.cycle_counter += 6;
                if (self.e and self.d_s.hl.dl == 0) {
                    self.resolved_address = @as(u16, self.d_s.hl.dh) << 8;
                    self.resolved_address |= (address +% self.x_s.hl.xl) & 0xff;
                } else {
                    self.resolved_address = (address +% self.d_s.d +% self.x_s.x) & 0xffff;
                }
                self.resolved_mask = 0x00ffff;
                self.cycle_counter += 6;
            },

            .zpy => {
                if (self.d_s.hl.dl != 0) self.cycle_counter += 6;
                if (self.e and self.d_s.hl.dl == 0) {
                    self.resolved_address = @as(u16, self.d_s.hl.dh) << 8;
                    self.resolved_address |= (address +% self.y_s.hl.yl) & 0xff;
                } else {
                    self.resolved_address = (address +% self.d_s.d +% self.y_s.y) & 0xffff;
                }
                self.resolved_mask = 0x00ffff;
                self.cycle_counter += 6;
            },

            .ind => {
                if (self.d_s.hl.dl != 0) self.cycle_counter += 6;
                var addr: u24 = 0;
                if (self.e and self.d_s.hl.dl == 0) {
                    addr = (@as(u16, self.d_s.hl.dh) << 8) | (address & 0xff);
                    self.resolved_address = self.read(addr);
                    addr = (@as(u16, self.d_s.hl.dh) << 8) | ((address +% 1) & 0xff);
                    self.resolved_address |= @as(u16, self.read(addr)) << 8;
                } else {
                    addr = (self.d_s.d +% address) & 0xffff;
                    self.resolved_address = self.read(addr);
                    addr = (self.d_s.d +% address +% 1) & 0xffff;
                    self.resolved_address |= @as(u16, self.read(addr)) << 8;
                }
                self.resolved_address |= @as(u24, self.db) << 16;
                self.resolved_mask = 0xffffff;
            },

            .idx => {
                if (self.d_s.hl.dl != 0) self.cycle_counter += 6;
                self.cycle_counter += 6;
                var addr: u24 = 0;
                if (self.e and self.d_s.hl.dl == 0) {
                    addr = (@as(u16, self.d_s.hl.dh) << 8) | ((address +% self.x_s.x) & 0xff);
                    self.resolved_address = self.read(addr);
                    addr = (@as(u16, self.d_s.hl.dh) << 8) | ((address +% self.x_s.x +% 1) & 0xff);
                    self.resolved_address |= @as(u16, self.read(addr)) << 8;
                } else if (self.e and self.d_s.hl.dl != 0) {
                    addr = @intCast((self.d_s.d +% address +% self.x_s.x) & 0xffff);
                    self.resolved_address = self.read(addr);
                    addr +%= 1;
                    if ((addr & 0xff) == 0) addr -%= 0x100;
                    self.resolved_address |= @as(u16, self.read(addr)) << 8;
                } else {
                    addr = (self.d_s.d +% address +% self.x_s.x) & 0xffff;
                    self.resolved_address = self.read(addr);
                    addr = (self.d_s.d +% address +% self.x_s.x +% 1) & 0xffff;
                    self.resolved_address |= @as(u16, self.read(addr)) << 8;
                }
                self.resolved_address |= @as(u24, self.db) << 16;
                self.resolved_mask = 0xffffff;
            },

            .idy => {
                if (self.d_s.hl.dl != 0) self.cycle_counter += 6;
                var addr: u24 = 0;
                if (self.e and self.d_s.hl.dl == 0) {
                    addr = (@as(u16, self.d_s.hl.dh) << 8) | (address & 0xff);
                    self.resolved_address = self.read(addr);
                    addr = (@as(u16, self.d_s.hl.dh) << 8) | ((address +% 1) & 0xff);
                    self.resolved_address |= @as(u16, self.read(addr)) << 8;
                } else {
                    addr = (self.d_s.d +% address) & 0xffff;
                    self.resolved_address = self.read(addr);
                    addr = (self.d_s.d +% address +% 1) & 0xffff;
                    self.resolved_address |= @as(u16, self.read(addr)) << 8;
                }
                page_crossed = checkPageCrossing(self.resolved_address, self.y_s.y);
                self.resolved_address = ((@as(u24, self.db) << 16) | self.resolved_address) +% self.y_s.y;
                self.resolved_mask = 0xffffff;
                if (!self.p.x or page_crossed or op.instruction == .INC or op.instruction == .DEC or op.instruction == .STA or op.instruction == .STZ or op.instruction == .ROR or op.instruction == .ROL or op.instruction == .ASL or op.instruction == .LSR) self.cycle_counter += 6;
            },

            .idl => {
                if (self.d_s.hl.dl != 0) self.cycle_counter += 6;
                var addr: u24 = (self.d_s.d +% address) & 0xffff;
                self.resolved_address = self.read(addr);
                addr = (self.d_s.d +% address +% 1) & 0xffff;
                self.resolved_address |= @as(u16, self.read(addr)) << 8;
                addr = (self.d_s.d +% address +% 2) & 0xffff;
                self.resolved_address |= @as(u24, self.read(addr)) << 16;
                self.resolved_mask = 0xffffff;
            },

            .idly => {
                if (self.d_s.hl.dl != 0) self.cycle_counter += 6;
                var addr: u24 = (self.d_s.d +% address) & 0xffff;
                self.resolved_address = self.read(addr);
                addr = (self.d_s.d +% address +% 1) & 0xffff;
                self.resolved_address |= @as(u16, self.read(addr)) << 8;
                addr = (self.d_s.d +% address +% 2) & 0xffff;
                self.resolved_address |= @as(u24, self.read(addr)) << 16;
                self.resolved_address +%= self.y_s.y;
                self.resolved_mask = 0xffffff;
            },

            .abs => {
                if (op.instruction == .JMP or op.instruction == .JSR) {
                    self.resolved_address = @as(u24, self.pb) << 16;
                } else {
                    self.resolved_address = @as(u24, self.db) << 16;
                }
                self.resolved_address |= address;
                self.resolved_mask = 0xffffff;
            },

            .abx => {
                page_crossed = checkPageCrossing(address, self.x_s.x);
                self.resolved_address = ((@as(u24, self.db) << 16) | address) +% self.x_s.x;
                self.resolved_mask = 0xffffff;
                if (!self.p.x or page_crossed or op.instruction == .INC or op.instruction == .DEC or op.instruction == .STA or op.instruction == .STZ or op.instruction == .ROR or op.instruction == .ROL or op.instruction == .ASL or op.instruction == .LSR) self.cycle_counter += 6;
            },

            .aby => {
                page_crossed = checkPageCrossing(address, self.y_s.y);
                self.resolved_address = ((@as(u24, self.db) << 16) | address) +% self.y_s.y;
                self.resolved_mask = 0xffffff;
                if (!self.p.x or page_crossed or op.instruction == .INC or op.instruction == .DEC or op.instruction == .STA or op.instruction == .STZ or op.instruction == .ROR or op.instruction == .ROL or op.instruction == .ASL or op.instruction == .LSR) self.cycle_counter += 6;
            },

            .abl => {
                self.resolved_address = address;
                self.resolved_mask = 0xffffff;
            },

            .ablx => {
                self.resolved_address = address +% self.x_s.x;
                self.resolved_mask = 0xffffff;
            },

            .abi => {
                var addr: u24 = address & 0xffff;
                self.resolved_address = self.read(addr);
                addr = (address +% 1) & 0xffff;
                self.resolved_address |= @as(u16, self.read(addr)) << 8;
                self.resolved_address |= @as(u24, self.pb) << 16;
                self.resolved_mask = 0xffffff;
            },

            .abil => {
                var addr: u24 = address & 0xffff;
                self.resolved_address = self.read(addr);
                addr = (address +% 1) & 0xffff;
                self.resolved_address |= @as(u16, self.read(addr)) << 8;
                addr = (address +% 2) & 0xffff;
                self.resolved_address |= @as(u24, self.read(addr)) << 16;
                self.resolved_mask = 0xffffff;
            },

            .abix => {
                self.cycle_counter += 6;
                var addr = (@as(u24, self.pb) << 16) | ((address +% self.x_s.x) & 0xffff);
                self.resolved_address = self.read(addr);
                addr = (@as(u24, self.pb) << 16) | ((address +% self.x_s.x +% 1) & 0xffff);
                self.resolved_address |= @as(u16, self.read(addr)) << 8;
                self.resolved_address |= (@as(u24, self.pb) << 16);
                self.resolved_mask = 0xffffff;
            },

            .rel => {
                if ((address & 0xff) < 0x80) {
                    const v: u16 = self.pc_s.pc +% @as(u16, @truncate(address));
                    self.resolved_address = (@as(u24, self.pb) << 16) | v;
                } else {
                    const v: i32 = @as(i32, self.pc_s.pc) + @as(i8, @bitCast(@as(u8, @truncate(address))));
                    self.resolved_address = (@as(u24, self.pb) << 16) | @as(u16, @truncate(@as(u32, @bitCast(v))));
                }
                page_crossed = (self.pc_s.pc & 0xff00) != (self.resolved_address & 0xff00);
                self.resolved_mask = 0xffffff;
            },

            .rell => {
                const pc: u16 = self.pc_s.pc +% @as(u16, @truncate(address));
                self.resolved_address = (@as(u24, self.pb) << 16) | pc;
                self.resolved_mask = 0xffffff;
            },

            .stk => {
                self.resolved_address = (address +% self.sp_s.s) & 0xffff;
                self.resolved_mask = 0x00ffff;
                self.cycle_counter += 6;
            },

            .stky => {
                var addr: u24 = (address +% self.sp_s.s) & 0xffff;
                self.cycle_counter += 6;
                self.resolved_address = self.read(addr);
                addr = (address +% self.sp_s.s +% 1) & 0xffff;
                self.resolved_address |= @as(u16, self.read(addr)) << 8;
                self.resolved_address |= @as(u24, self.db) << 16;
                self.resolved_address +%= self.y_s.y;
                self.resolved_mask = 0xffffff;
                self.cycle_counter += 6;
            },
        }

        return page_crossed;
    }

    fn fetchOpcode(self: *CPU, page_crossed: *bool) opcode.Opcode {
        var addr = (@as(u24, self.pb) << 16) | self.pc_s.pc;
        const op = opcode.Opcodes[self.read(addr)];
        self.pc_s.pc +%= 1;

        var len = op.length.v - 1;
        if (op.length.m and self.p.m) len -= 1;
        if (op.length.x and self.p.x) len -= 1;
        var arg: u24 = 0;
        for (0..len) |i| {
            addr = (@as(u24, self.pb) << 16) | self.pc_s.pc;
            const v = @as(u24, self.read(addr));
            arg |= v << @as(u5, @truncate(8 * i));
            self.pc_s.pc +%= 1;
        }

        page_crossed.* = self.resolveAddress(op, arg);
        return op;
    }

    pub fn irq(self: *CPU, irq_type: IRQType) void {
        if (self.state == .stop and irq_type != .reset) return;

        if (self.state == .wait) {
            self.cycle_counter += 12;
            self.state = .normal;
        }

        const vector: u16 = @as(u16, switch (irq_type) {
            .cop => if (self.e) 0xfff4 else 0xffe4,
            .abort => if (self.e) 0xfff8 else 0xffe8,
            .nmi => if (self.e) 0xfffa else 0xffea,
            .irq => if (self.e) 0xfffe else 0xffee,
            .reset => 0xfffc,
        });

        self.cycle_counter += 12;

        if (self.e) {
            self.sp_s.hl.sh = 1;
            var p: u8 = @bitCast(self.p);
            p &= 0xdf;
            self.push(@intCast(self.pc_s.pc >> 8));
            self.push(@intCast(self.pc_s.pc & 0xff));
            self.push(p);
            self.pc_s.pc = self.read(vector);
            self.pc_s.pc |= @as(u16, self.read(vector + 1)) << 8;
            self.pb = 0;
        } else {
            self.push(self.pb);
            self.push(@intCast(self.pc_s.pc >> 8));
            self.push(@intCast(self.pc_s.pc & 0xff));
            self.push(@bitCast(self.p));
            self.pc_s.pc = self.read(vector);
            self.pc_s.pc |= @as(u16, self.read(vector + 1)) << 8;
            self.pb = 0;
        }

        self.p.d = false;
        self.p.i = true;
        self.state = .normal;
    }

    pub fn process(self: *CPU) void {
        self.cycle_counter -|= 1;
        if (self.cycle_counter > 0) return;

        if (self.nmi_requested) {
            if (!self.nmi_occurred) {
                self.nmi_occurred = true;
                self.irq(.nmi);
                return;
            }
        } else {
            self.nmi_occurred = false;
        }

        if (self.irq_requested) {
            if (!self.p.i) {
                self.irq(.irq);
                return;
            } else if (self.state == .wait) {
                self.cycle_counter += 12;
                self.state = .normal;
            }
        }

        if (self.halt or self.state != .normal) return;

        var page_crossed: bool = false;
        const op = self.fetchOpcode(&page_crossed);

        switch (op.instruction) {
            .ADC => {
                if (self.p.m) {
                    const a: u8 = self.a_s.hl.a;
                    const b: u8 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    const carry: u8 = if (self.p.c) 1 else 0;
                    if (self.p.d) {
                        var al: u16 = (a & 0xf) + (b & 0xf) + carry;
                        if (al >= 0xa) al = ((al + 0x6) & 0xf) + 0x10;
                        var result: u16 = @as(u16, a & 0xf0) + @as(u16, b & 0xf0) + al;

                        const as: i8 = @bitCast(@as(u8, a & 0xf0));
                        const bs: i8 = @bitCast(@as(u8, b & 0xf0));
                        const v: i16 = @as(i16, as) + @as(i16, bs) + @as(i16, @bitCast(al));
                        self.p.v = v < -128 or v > 127;

                        if (result >= 0xa0) result += 0x60;
                        self.a_s.hl.a = @as(u8, @truncate(result));
                        self.p.z = self.a_s.hl.a == 0;
                        self.p.c = result >= 0x100;
                        self.p.n = (result & 0x80) > 0;
                    } else {
                        const sum1 = @addWithOverflow(a, b);
                        const sum2 = @addWithOverflow(sum1.@"0", carry);
                        const result = sum2.@"0";
                        self.a_s.hl.a = result;
                        self.p.z = result == 0;
                        self.p.c = sum1.@"1" == 1 or sum2.@"1" == 1;
                        self.p.n = (result & 0x80) > 0;
                        self.p.v = ((a ^ result) & (b ^ result) & 0x80) > 0;
                    }
                } else {
                    const a: u16 = self.a_s.c;
                    const b: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    const carry: u16 = if (self.p.c) 1 else 0;

                    if (self.p.d) {
                        var bcd_carry: u16 = 0;
                        {
                            var al: u16 = (a & 0xf) + (b & 0xf) + carry;
                            if (al >= 0xa) al = ((al + 0x6) & 0xf) + 0x10;
                            var bcd: u16 = (a & 0xf0) + (b & 0xf0) + al;
                            if (bcd >= 0xa0) bcd += 0x60;
                            self.a_s.hl.a = @truncate(bcd);
                            bcd_carry = if (bcd > 0xff) 1 else 0;
                        }

                        {
                            var al: u16 = ((a >> 8) & 0xf) + ((b >> 8) & 0xf) + bcd_carry;
                            if (al >= 0xa) al = ((al + 0x6) & 0xf) + 0x10;
                            var bcd: u16 = ((a >> 8) & 0xf0) + ((b >> 8) & 0xf0) + al;

                            const as: i8 = @bitCast(@as(u8, @truncate((a >> 8) & 0xf0)));
                            const bs: i8 = @bitCast(@as(u8, @truncate((b >> 8) & 0xf0)));
                            const v: i16 = @as(i16, as) + @as(i16, bs) + @as(i16, @bitCast(al));
                            self.p.v = v < -128 or v > 127;

                            if (bcd >= 0xa0) bcd += 0x60;
                            self.a_s.hl.b = @truncate(bcd);
                            self.p.c = bcd >= 0x100;
                            self.p.z = self.a_s.c == 0;
                            self.p.n = (self.a_s.hl.b & 0x80) > 0;
                        }
                    } else {
                        const sum1 = @addWithOverflow(a, b);
                        const sum2 = @addWithOverflow(sum1.@"0", carry);
                        const result = sum2.@"0";
                        self.a_s.c = result;
                        self.p.c = sum1.@"1" == 1 or sum2.@"1" == 1;
                        self.p.v = ((a ^ result) & (b ^ result) & 0x8000) > 0;
                        self.p.z = result == 0;
                        self.p.n = (result & 0x8000) > 0;
                    }
                }
            },

            .AND => {
                if (self.p.m) {
                    const v: u8 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    self.a_s.hl.a &= v;
                    self.p.z = self.a_s.hl.a == 0;
                    self.p.n = (self.a_s.hl.a & 0x80) > 0;
                } else {
                    const v: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    self.a_s.c &= v;
                    self.p.z = self.a_s.c == 0;
                    self.p.n = (self.a_s.c & 0x8000) > 0;
                }
            },

            .ASL => {
                if (self.p.m) {
                    if (op.mode == .acc) {
                        self.p.c = (self.a_s.hl.a & 0x80) > 0;
                        const v = self.a_s.hl.a << 1;
                        self.a_s.hl.a = v;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x80) > 0;
                        self.cycle_counter += 6;
                    } else {
                        var v = self.read(self.resolved_address);
                        self.p.c = (v & 0x80) > 0;
                        v <<= 1;
                        self.cycle_counter += 6;
                        self.write(self.resolved_address, v);
                        self.p.z = v == 0;
                        self.p.n = (v & 0x80) > 0;
                    }
                } else {
                    if (op.mode == .acc) {
                        self.p.c = (self.a_s.c & 0x8000) > 0;
                        const v = self.a_s.c << 1;
                        self.a_s.c = v;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x8000) > 0;
                        self.cycle_counter += 6;
                    } else {
                        const addr1 = self.resolved_address;
                        const addr2 = self.nextResolvedAddress();
                        var v: u16 = self.read(addr1);
                        v |= @as(u16, self.read(addr2)) << 8;
                        self.p.c = (v & 0x8000) > 0;
                        v <<= 1;
                        self.cycle_counter += 6;
                        self.write(addr1, @truncate(v));
                        self.write(addr2, @truncate(v >> 8));
                        self.p.z = v == 0;
                        self.p.n = (v & 0x8000) > 0;
                    }
                }
            },

            .BCC => {
                if (!self.p.c) {
                    self.pc_s.pc = @truncate(self.resolved_address);
                    self.cycle_counter += 6 * (1 + @as(u16, if (self.e and page_crossed) 1 else 0));
                }
            },

            .BCS => {
                if (self.p.c) {
                    self.pc_s.pc = @truncate(self.resolved_address);
                    self.cycle_counter += 6 * (1 + @as(u16, if (self.e and page_crossed) 1 else 0));
                }
            },

            .BEQ => {
                if (self.p.z) {
                    self.pc_s.pc = @truncate(self.resolved_address);
                    self.cycle_counter += 6 * (1 + @as(u16, if (self.e and page_crossed) 1 else 0));
                }
            },

            .BMI => {
                if (self.p.n) {
                    self.pc_s.pc = @truncate(self.resolved_address);
                    self.cycle_counter += 6 * (1 + @as(u16, if (self.e and page_crossed) 1 else 0));
                }
            },

            .BNE => {
                if (!self.p.z) {
                    self.pc_s.pc = @truncate(self.resolved_address);
                    self.cycle_counter += 6 * (1 + @as(u16, if (self.e and page_crossed) 1 else 0));
                }
            },

            .BPL => {
                if (!self.p.n) {
                    self.pc_s.pc = @truncate(self.resolved_address);
                    self.cycle_counter += 6 * (1 + @as(u16, if (self.e and page_crossed) 1 else 0));
                }
            },

            .BRA => {
                self.pc_s.pc = @truncate(self.resolved_address);
                self.cycle_counter += 6 * (1 + @as(u16, if (self.e and page_crossed) 1 else 0));
            },

            .BRL => {
                self.pc_s.pc = @truncate(self.resolved_address);
                self.cycle_counter += 6;
            },

            .BVC => {
                if (!self.p.v) {
                    self.pc_s.pc = @truncate(self.resolved_address);
                    self.cycle_counter += 6 * (1 + @as(u16, if (self.e and page_crossed) 1 else 0));
                }
            },

            .BVS => {
                if (self.p.v) {
                    self.pc_s.pc = @truncate(self.resolved_address);
                    self.cycle_counter += 6 * (1 + @as(u16, if (self.e and page_crossed) 1 else 0));
                }
            },

            .BIT => {
                if (self.p.m) {
                    const v: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    self.p.z = (self.a_s.hl.a & v) == 0;
                    if (op.mode != .imm) {
                        self.p.n = v & 0x80 > 0;
                        self.p.v = v & 0x40 > 0;
                    }
                } else {
                    const v: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    self.p.z = (self.a_s.c & v) == 0;
                    if (op.mode != .imm) {
                        self.p.n = v & 0x8000 > 0;
                        self.p.v = v & 0x4000 > 0;
                    }
                }
            },

            .BRK => {
                _ = self.read((@as(u24, self.pb) << 16) | self.pc_s.pc);
                const pc = self.pc_s.pc +% 1;
                if (self.e) {
                    var p: u8 = @bitCast(self.p);
                    p |= 0x20;
                    self.push(@truncate(pc >> 8));
                    self.push(@truncate(pc));
                    self.push(p);
                    self.pc_s.pc = self.read(0xfffe);
                    self.pc_s.pc |= @as(u16, self.read(0xffff)) << 8;
                    self.pb = 0;
                } else {
                    self.push(self.pb);
                    self.push(@truncate(pc >> 8));
                    self.push(@truncate(pc));
                    self.push(@bitCast(self.p));
                    self.pc_s.pc = self.read(0xffe6);
                    self.pc_s.pc |= @as(u16, self.read(0xffe7)) << 8;
                    self.pb = 0;
                }
                self.p.d = false;
                self.p.i = true;
            },

            .CLC => {
                self.p.c = false;
                self.cycle_counter += 6;
            },

            .CLD => {
                self.p.d = false;
                self.cycle_counter += 6;
            },

            .CLI => {
                self.p.i = false;
                self.cycle_counter += 6;
            },

            .CLV => {
                self.p.v = false;
                self.cycle_counter += 6;
            },

            .CMP => {
                if (self.p.m) {
                    const a: u8 = self.a_s.hl.a;
                    const b: u8 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    const sub = @subWithOverflow(a, b);
                    const result = sub.@"0";
                    self.p.z = result == 0;
                    self.p.c = sub.@"1" == 0 and sub.@"1" == 0;
                    self.p.n = (result & 0x80) > 0;
                } else {
                    const a: u16 = self.a_s.c;
                    const b: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    const sub = @subWithOverflow(a, b);
                    const result = sub.@"0";
                    self.p.z = result == 0;
                    self.p.c = sub.@"1" == 0 and sub.@"1" == 0;
                    self.p.n = (result & 0x8000) > 0;
                }
            },

            .COP => {
                if (self.e) {
                    var p: u8 = @bitCast(self.p);
                    p |= 0x20;
                    self.push(self.pc_s.hl.pch);
                    self.push(self.pc_s.hl.pcl);
                    self.push(p);
                    self.pc_s.pc = self.read(0xfff4);
                    self.pc_s.pc |= @as(u16, self.read(0xfff5)) << 8;
                    self.pb = 0;
                } else {
                    self.push(self.pb);
                    self.push(self.pc_s.hl.pch);
                    self.push(self.pc_s.hl.pcl);
                    self.push(@bitCast(self.p));
                    self.pc_s.pc = self.read(0xffe4);
                    self.pc_s.pc |= @as(u16, self.read(0xffe5)) << 8;
                    self.pb = 0;
                }
                self.p.d = false;
                self.p.i = true;
            },

            .CPX => {
                if (self.p.x) {
                    const a: u8 = self.x_s.hl.xl;
                    const b: u8 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    const sub = @subWithOverflow(a, b);
                    const result = sub.@"0";
                    self.p.z = result == 0;
                    self.p.c = sub.@"1" == 0 and sub.@"1" == 0;
                    self.p.n = (result & 0x80) > 0;
                } else {
                    const a: u16 = self.x_s.x;
                    const b: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    const sub = @subWithOverflow(a, b);
                    const result = sub.@"0";
                    self.p.z = result == 0;
                    self.p.c = sub.@"1" == 0 and sub.@"1" == 0;
                    self.p.n = (result & 0x8000) > 0;
                }
            },

            .CPY => {
                if (self.p.x) {
                    const a: u8 = self.y_s.hl.yl;
                    const b: u8 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    const sub = @subWithOverflow(a, b);
                    const result = sub.@"0";
                    self.p.z = result == 0;
                    self.p.c = sub.@"1" == 0 and sub.@"1" == 0;
                    self.p.n = (result & 0x80) > 0;
                } else {
                    const a: u16 = self.y_s.y;
                    const b: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    const sub = @subWithOverflow(a, b);
                    const result = sub.@"0";
                    self.p.z = result == 0;
                    self.p.c = sub.@"1" == 0 and sub.@"1" == 0;
                    self.p.n = (result & 0x8000) > 0;
                }
            },

            .DEC => {
                if (op.mode == .acc) {
                    if (self.p.m) {
                        self.a_s.hl.a -%= 1;
                        self.p.z = self.a_s.hl.a == 0;
                        self.p.n = (self.a_s.hl.a & 0x80) > 0;
                    } else {
                        self.a_s.c -%= 1;
                        self.p.z = self.a_s.c == 0;
                        self.p.n = (self.a_s.c & 0x8000) > 0;
                    }
                    self.cycle_counter += 6;
                } else {
                    if (self.p.m) {
                        var v = self.read(self.resolved_address);

                        v -%= 1;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x80) > 0;
                        self.cycle_counter += 6;

                        self.write(self.resolved_address, v);
                    } else {
                        const addr1 = self.resolved_address;
                        const addr2 = self.nextResolvedAddress();
                        var v: u16 = self.read(addr1);
                        v |= @as(u16, self.read(addr2)) << 8;

                        v -%= 1;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x8000) > 0;
                        self.cycle_counter += 6;

                        self.write(addr1, @truncate(v));
                        self.write(addr2, @truncate(v >> 8));
                    }
                }
            },

            .DEX => {
                if (self.p.x) {
                    self.x_s.hl.xl -%= 1;
                    self.p.z = self.x_s.hl.xl == 0;
                    self.p.n = (self.x_s.hl.xl & 0x80) > 0;
                } else {
                    self.x_s.x -%= 1;
                    self.p.z = self.x_s.x == 0;
                    self.p.n = (self.x_s.x & 0x8000) > 0;
                }
                self.cycle_counter += 6;
            },

            .DEY => {
                if (self.p.x) {
                    self.y_s.hl.yl -%= 1;
                    self.p.z = self.y_s.hl.yl == 0;
                    self.p.n = (self.y_s.hl.yl & 0x80) > 0;
                } else {
                    self.y_s.y -%= 1;
                    self.p.z = self.y_s.y == 0;
                    self.p.n = (self.y_s.y & 0x8000) > 0;
                }
                self.cycle_counter += 6;
            },

            .EOR => {
                if (self.p.m) {
                    const v: u8 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    self.a_s.hl.a ^= v;
                    self.p.z = self.a_s.hl.a == 0;
                    self.p.n = (self.a_s.hl.a & 0x80) > 0;
                } else {
                    const v: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    self.a_s.c ^= v;
                    self.p.z = self.a_s.c == 0;
                    self.p.n = (self.a_s.c & 0x8000) > 0;
                }
            },

            .INC => {
                if (op.mode == .acc) {
                    if (self.p.m) {
                        self.a_s.hl.a +%= 1;
                        self.p.z = self.a_s.hl.a == 0;
                        self.p.n = (self.a_s.hl.a & 0x80) > 0;
                    } else {
                        self.a_s.c +%= 1;
                        self.p.z = self.a_s.c == 0;
                        self.p.n = (self.a_s.c & 0x8000) > 0;
                    }
                    self.cycle_counter += 6;
                } else {
                    if (self.p.m) {
                        var v = self.read(self.resolved_address);

                        v +%= 1;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x80) > 0;
                        self.cycle_counter += 6;

                        self.write(self.resolved_address, v);
                    } else {
                        const addr1 = self.resolved_address;
                        const addr2 = self.nextResolvedAddress();
                        var v: u16 = self.read(addr1);
                        v |= @as(u16, self.read(addr2)) << 8;

                        v +%= 1;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x8000) > 0;
                        self.cycle_counter += 6;

                        self.write(addr1, @truncate(v));
                        self.write(addr2, @truncate(v >> 8));
                    }
                }
            },

            .INX => {
                if (self.p.x) {
                    self.x_s.hl.xl +%= 1;
                    self.p.z = self.x_s.hl.xl == 0;
                    self.p.n = (self.x_s.hl.xl & 0x80) > 0;
                } else {
                    self.x_s.x +%= 1;
                    self.p.z = self.x_s.x == 0;
                    self.p.n = (self.x_s.x & 0x8000) > 0;
                }
                self.cycle_counter += 6;
            },

            .INY => {
                if (self.p.x) {
                    self.y_s.hl.yl +%= 1;
                    self.p.z = self.y_s.hl.yl == 0;
                    self.p.n = (self.y_s.hl.yl & 0x80) > 0;
                } else {
                    self.y_s.y +%= 1;
                    self.p.z = self.y_s.y == 0;
                    self.p.n = (self.y_s.y & 0x8000) > 0;
                }
                self.cycle_counter += 6;
            },

            .JMP => {
                self.pc_s.pc = @truncate(self.resolved_address);
                self.pb = @truncate(self.resolved_address >> 16);
            },

            .JSL => {
                const pc = self.pc_s.pc -% 1;
                const e = self.e;
                self.e = false;
                self.cycle_counter += 6;
                self.push(self.pb);
                self.push(@truncate(pc >> 8));
                self.push(@truncate(pc));
                self.e = e;
                self.pb = @truncate(self.resolved_address >> 16);
                self.pc_s.pc = @truncate(self.resolved_address);
            },

            .JSR => {
                const pc = self.pc_s.pc -% 1;
                if (op.mode == .abs) self.cycle_counter += 6;
                self.push(@truncate(pc >> 8));
                self.push(@truncate(pc));
                self.pc_s.pc = @truncate(self.resolved_address);
            },

            .LDA => {
                if (self.p.m) {
                    const v: u8 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    self.a_s.hl.a = v;
                    self.p.z = self.a_s.hl.a == 0;
                    self.p.n = (self.a_s.hl.a & 0x80) > 0;
                } else {
                    const v: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    self.a_s.c = v;
                    self.p.z = self.a_s.c == 0;
                    self.p.n = (self.a_s.c & 0x8000) > 0;
                }
            },

            .LDX => {
                if (self.p.x) {
                    const v: u8 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    self.x_s.hl.xl = v;
                    self.p.z = self.x_s.hl.xl == 0;
                    self.p.n = (self.x_s.hl.xl & 0x80) > 0;
                } else {
                    const v: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    self.x_s.x = v;
                    self.p.z = self.x_s.x == 0;
                    self.p.n = (self.x_s.x & 0x8000) > 0;
                }
            },

            .LDY => {
                if (self.p.x) {
                    const v: u8 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    self.y_s.hl.yl = v;
                    self.p.z = self.y_s.hl.yl == 0;
                    self.p.n = (self.y_s.hl.yl & 0x80) > 0;
                } else {
                    const v: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    self.y_s.y = v;
                    self.p.z = self.y_s.y == 0;
                    self.p.n = (self.y_s.y & 0x8000) > 0;
                }
            },

            .LSR => {
                if (self.p.m) {
                    if (op.mode == .acc) {
                        self.p.c = (self.a_s.hl.a & 1) > 0;
                        const v = self.a_s.hl.a >> 1;
                        self.a_s.hl.a = v;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x80) > 0;
                        self.cycle_counter += 6;
                    } else {
                        var v = self.read(self.resolved_address);
                        self.p.c = (v & 1) > 0;
                        v >>= 1;
                        self.cycle_counter += 6;
                        self.write(self.resolved_address, v);
                        self.p.z = v == 0;
                        self.p.n = (v & 0x80) > 0;
                    }
                } else {
                    if (op.mode == .acc) {
                        self.p.c = (self.a_s.c & 1) > 0;
                        const v = self.a_s.c >> 1;
                        self.a_s.c = v;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x8000) > 0;
                        self.cycle_counter += 6;
                    } else {
                        const addr1 = self.resolved_address;
                        const addr2 = self.nextResolvedAddress();
                        var v: u16 = self.read(addr1);
                        v |= @as(u16, self.read(addr2)) << 8;
                        self.p.c = (v & 1) > 0;
                        v >>= 1;
                        self.cycle_counter += 6;
                        self.write(addr1, @truncate(v));
                        self.write(addr2, @truncate(v >> 8));
                        self.p.z = v == 0;
                        self.p.n = (v & 0x8000) > 0;
                    }
                }
            },

            .MVN => {
                if (self.a_s.c > 0) self.pc_s.pc -%= 3;
                const src: u24 = (@as(u24, self.resolved_address >> 8) << 16) | self.x_s.x;
                const dst: u24 = (@as(u24, self.resolved_address & 0xff) << 16) | self.y_s.y;
                self.write(dst, self.read(src));
                self.a_s.c -%= 1;
                if (self.p.x) {
                    self.x_s.hl.xl +%= 1;
                    self.y_s.hl.yl +%= 1;
                } else {
                    self.x_s.x +%= 1;
                    self.y_s.y +%= 1;
                }
                self.db = @truncate(self.resolved_address & 0xff);
            },

            .MVP => {
                if (self.a_s.c > 0) self.pc_s.pc -%= 3;
                const src: u24 = (@as(u24, self.resolved_address >> 8) << 16) | self.x_s.x;
                const dst: u24 = (@as(u24, self.resolved_address & 0xff) << 16) | self.y_s.y;
                self.write(dst, self.read(src));
                self.a_s.c -%= 1;
                if (self.p.x) {
                    self.x_s.hl.xl -%= 1;
                    self.y_s.hl.yl -%= 1;
                } else {
                    self.x_s.x -%= 1;
                    self.y_s.y -%= 1;
                }
                self.db = @truncate(self.resolved_address & 0xff);
            },

            .ORA => {
                if (self.p.m) {
                    const v: u8 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    self.a_s.hl.a |= v;
                    self.p.z = self.a_s.hl.a == 0;
                    self.p.n = (self.a_s.hl.a & 0x80) > 0;
                } else {
                    const v: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    self.a_s.c |= v;
                    self.p.z = self.a_s.c == 0;
                    self.p.n = (self.a_s.c & 0x8000) > 0;
                }
            },

            .PEA => {
                const e = self.e;
                self.e = false;
                self.push(@truncate(self.resolved_address >> 8));
                self.push(@truncate(self.resolved_address));
                self.e = e;
            },

            .PEI => {
                const e = self.e;
                self.e = false;
                var addr = self.resolved_address;
                var v: u16 = self.read(addr);
                addr = self.nextResolvedAddress();
                v |= @as(u16, self.read(addr)) << 8;
                self.push(@truncate(v >> 8));
                self.push(@truncate(v));
                self.e = e;
            },

            .PER => {
                const v: u16 = self.pc_s.pc +% @as(u16, @truncate(self.resolved_address));
                const e = self.e;
                self.e = false;
                self.cycle_counter += 6;
                self.push(@truncate(v >> 8));
                self.push(@truncate(v));
                self.e = e;
            },

            .PHA => {
                self.cycle_counter += 6;
                if (self.p.m) {
                    self.push(self.a_s.hl.a);
                } else {
                    self.push(self.a_s.hl.b);
                    self.push(self.a_s.hl.a);
                }
            },

            .PHB => {
                self.cycle_counter += 6;
                self.push(self.db);
            },

            .PHD => {
                self.cycle_counter += 6;
                const e = self.e;
                self.e = false;
                self.push(self.d_s.hl.dh);
                self.push(self.d_s.hl.dl);
                self.e = e;
            },

            .PHK => {
                self.cycle_counter += 6;
                self.push(self.pb);
            },

            .PHP => {
                self.cycle_counter += 6;
                self.push(@bitCast(self.p));
            },

            .PHX => {
                self.cycle_counter += 6;
                if (self.p.x) {
                    self.push(self.x_s.hl.xl);
                } else {
                    self.push(self.x_s.hl.xh);
                    self.push(self.x_s.hl.xl);
                }
            },

            .PHY => {
                self.cycle_counter += 6;
                if (self.p.x) {
                    self.push(self.y_s.hl.yl);
                } else {
                    self.push(self.y_s.hl.yh);
                    self.push(self.y_s.hl.yl);
                }
            },

            .PLA => {
                self.cycle_counter += 12;
                if (self.p.m) {
                    self.a_s.hl.a = self.pop();
                    self.p.z = self.a_s.hl.a == 0;
                    self.p.n = (self.a_s.hl.a & 0x80) > 0;
                } else {
                    self.a_s.hl.a = self.pop();
                    self.a_s.hl.b = self.pop();
                    self.p.z = self.a_s.c == 0;
                    self.p.n = (self.a_s.c & 0x8000) > 0;
                }
            },

            .PLB => {
                self.cycle_counter += 12;
                if (self.e) {
                    self.sp_s.hl.sl +%= 1;
                    if (self.sp_s.hl.sl == 0) {
                        // undocumented behavior
                        self.db = self.read(0x200);
                    } else {
                        const addr = 0x100 | @as(u16, self.sp_s.hl.sl);
                        self.db = self.read(addr);
                    }
                } else {
                    self.sp_s.s +%= 1;
                    self.db = self.read(self.sp_s.s);
                }

                self.p.z = self.db == 0;
                self.p.n = (self.db & 0x80) > 0;
            },

            .PLD => {
                self.cycle_counter += 12;
                const e = self.e;
                self.e = false;
                self.d_s.hl.dl = self.pop();
                self.d_s.hl.dh = self.pop();
                self.e = e;
                self.p.z = self.d_s.d == 0;
                self.p.n = (self.d_s.d & 0x8000) > 0;
            },

            .PLP => {
                self.cycle_counter += 12;
                self.p = @bitCast(self.pop());
                if (self.p.x) {
                    self.x_s.hl.xh = 0;
                    self.y_s.hl.yh = 0;
                }
            },

            .PLX => {
                self.cycle_counter += 12;
                if (self.p.x) {
                    self.x_s.hl.xl = self.pop();
                    self.p.z = self.x_s.hl.xl == 0;
                    self.p.n = (self.x_s.hl.xl & 0x80) > 0;
                } else {
                    self.x_s.hl.xl = self.pop();
                    self.x_s.hl.xh = self.pop();
                    self.p.z = self.x_s.x == 0;
                    self.p.n = (self.x_s.x & 0x8000) > 0;
                }
            },

            .PLY => {
                self.cycle_counter += 12;
                if (self.p.x) {
                    self.y_s.hl.yl = self.pop();
                    self.p.z = self.y_s.hl.yl == 0;
                    self.p.n = (self.y_s.hl.yl & 0x80) > 0;
                } else {
                    self.y_s.hl.yl = self.pop();
                    self.y_s.hl.yh = self.pop();
                    self.p.z = self.y_s.y == 0;
                    self.p.n = (self.y_s.y & 0x8000) > 0;
                }
            },

            .REP => {
                self.p = @bitCast(@as(u8, @bitCast(self.p)) & ~@as(u8, @truncate(self.resolved_address)));
                if (self.p.x) {
                    self.x_s.hl.xh = 0;
                    self.y_s.hl.yh = 0;
                }
                self.cycle_counter += 6;
            },

            .ROL => {
                const carry: u8 = if (self.p.c) 1 else 0;
                if (self.p.m) {
                    if (op.mode == .acc) {
                        self.p.c = (self.a_s.hl.a & 0x80) > 0;
                        const v = (self.a_s.hl.a << 1) | carry;
                        self.a_s.hl.a = v;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x80) > 0;
                        self.cycle_counter += 6;
                    } else {
                        var v = self.read(self.resolved_address);
                        self.p.c = (v & 0x80) > 0;
                        v = (v << 1) | carry;
                        self.cycle_counter += 6;
                        self.write(self.resolved_address, v);
                        self.p.z = v == 0;
                        self.p.n = (v & 0x80) > 0;
                    }
                } else {
                    if (op.mode == .acc) {
                        self.p.c = (self.a_s.c & 0x8000) > 0;
                        const v = (self.a_s.c << 1) | carry;
                        self.a_s.c = v;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x8000) > 0;
                        self.cycle_counter += 6;
                    } else {
                        const addr1 = self.resolved_address;
                        const addr2 = self.nextResolvedAddress();
                        var v: u16 = self.read(addr1);
                        v |= @as(u16, self.read(addr2)) << 8;
                        self.p.c = (v & 0x8000) > 0;
                        v = (v << 1) | carry;
                        self.cycle_counter += 6;
                        self.write(addr1, @truncate(v));
                        self.write(addr2, @truncate(v >> 8));
                        self.p.z = v == 0;
                        self.p.n = (v & 0x8000) > 0;
                    }
                }
            },

            .ROR => {
                if (self.p.m) {
                    const carry: u8 = if (self.p.c) 0x80 else 0;
                    if (op.mode == .acc) {
                        self.p.c = (self.a_s.hl.a & 1) > 0;
                        const v = (self.a_s.hl.a >> 1) | carry;
                        self.a_s.hl.a = v;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x80) > 0;
                        self.cycle_counter += 6;
                    } else {
                        var v = self.read(self.resolved_address);
                        self.p.c = (v & 1) > 0;
                        v = (v >> 1) | carry;
                        self.cycle_counter += 6;
                        self.write(self.resolved_address, v);
                        self.p.z = v == 0;
                        self.p.n = (v & 0x80) > 0;
                    }
                } else {
                    const carry: u16 = if (self.p.c) 0x8000 else 0;
                    if (op.mode == .acc) {
                        self.p.c = (self.a_s.c & 1) > 0;
                        const v = (self.a_s.c >> 1) | carry;
                        self.a_s.c = v;
                        self.p.z = v == 0;
                        self.p.n = (v & 0x8000) > 0;
                        self.cycle_counter += 6;
                    } else {
                        const addr1 = self.resolved_address;
                        const addr2 = self.nextResolvedAddress();
                        var v: u16 = self.read(addr1);
                        v |= @as(u16, self.read(addr2)) << 8;
                        self.p.c = (v & 1) > 0;
                        v = (v >> 1) | carry;
                        self.cycle_counter += 6;
                        self.write(addr1, @truncate(v));
                        self.write(addr2, @truncate(v >> 8));
                        self.p.z = v == 0;
                        self.p.n = (v & 0x8000) > 0;
                    }
                }
            },

            .RTI => {
                self.cycle_counter += 12;
                self.p = @bitCast(self.pop());
                self.pc_s.hl.pcl = self.pop();
                self.pc_s.hl.pch = self.pop();
                if (!self.e) self.pb = self.pop();
                if (self.p.x) {
                    self.x_s.hl.xh = 0;
                    self.y_s.hl.yh = 0;
                }
            },

            .RTL => {
                self.cycle_counter += 12;
                const e = self.e;
                self.e = false;
                self.pc_s.hl.pcl = self.pop();
                self.pc_s.hl.pch = self.pop();
                self.pc_s.pc +%= 1;
                self.pb = self.pop();
                self.e = e;
            },

            .RTS => {
                self.cycle_counter += 12;
                self.pc_s.hl.pcl = self.pop();
                self.pc_s.hl.pch = self.pop();
                self.pc_s.pc +%= 1;
                self.cycle_counter += 6;
            },

            .SBC => {
                if (self.p.m) {
                    const a: u8 = self.a_s.hl.a;
                    const b: u8 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => self.read(self.resolved_address),
                    };
                    const carry: u8 = if (self.p.c) 0 else 1;
                    const sub1 = @subWithOverflow(a, b);
                    const sub2 = @subWithOverflow(sub1.@"0", carry);
                    const result = sub2.@"0";
                    self.a_s.hl.a = result;
                    self.p.z = result == 0;
                    self.p.n = (result & 0x80) > 0;
                    if (self.p.d) {
                        var al: i16 = @as(i16, a & 0xf) - @as(i16, b & 0xf) + @as(i16, if (self.p.c) 1 else 0) - 1;
                        if (al < 0) al = ((al - 0x6) & 0xf) - 0x10;
                        var bcd: i16 = @as(i16, a & 0xf0) - @as(i16, b & 0xf0) + al;
                        if (bcd < 0) bcd -= 0x60;
                        self.a_s.hl.a = @truncate(@as(u16, @bitCast(bcd)));
                        self.p.z = self.a_s.hl.a == 0;
                        self.p.n = (bcd & 0x80) > 0;
                    }
                    self.p.c = sub1.@"1" == 0 and sub2.@"1" == 0;
                    self.p.v = ((a ^ result) & ((255 - b) ^ result) & 0x80) > 0;
                } else {
                    const a: u16 = self.a_s.c;
                    const b: u16 = switch (op.mode) {
                        .imm => @truncate(self.resolved_address),
                        else => blk: {
                            var addr = self.resolved_address;
                            var b: u16 = self.read(addr);
                            addr = self.nextResolvedAddress();
                            b |= @as(u16, self.read(addr)) << 8;
                            break :blk b;
                        },
                    };
                    const carry: u16 = if (self.p.c) 0 else 1;
                    const sub1 = @subWithOverflow(a, b);
                    const sub2 = @subWithOverflow(sub1.@"0", carry);
                    const result = sub2.@"0";
                    self.a_s.c = result;
                    self.p.z = result == 0;
                    self.p.n = (result & 0x8000) > 0;

                    if (self.p.d) {
                        var bcd_carry: bool = true;
                        {
                            var al: i16 = @as(i16, @bitCast(a & 0xf)) - @as(i16, @bitCast(b & 0xf)) + @as(i16, if (self.p.c) 1 else 0) - 1;
                            if (al < 0) al = ((al - 0x6) & 0xf) - 0x10;
                            var bcd: i16 = @as(i16, @bitCast(a & 0xf0)) - @as(i16, @bitCast(b & 0xf0)) + al;
                            if (bcd < 0) {
                                bcd -= 0x60;
                                bcd_carry = false;
                            }
                            self.a_s.hl.a = @truncate(@as(u16, @bitCast(bcd)));
                        }

                        {
                            var al: i16 = @as(i16, @as(u8, @truncate((a >> 8) & 0xf))) - @as(i16, @as(u8, @truncate((b >> 8) & 0xf))) + @as(i16, if (bcd_carry) 1 else 0) - 1;
                            if (al < 0) al = ((al - 0x6) & 0xf) - 0x10;
                            var bcd: i16 = @as(i16, @as(u8, @truncate((a >> 8) & 0xf0))) - @as(i16, @as(u8, @truncate((b >> 8) & 0xf0))) + al;
                            if (bcd < 0) bcd -= 0x60;
                            self.a_s.hl.b = @truncate(@as(u16, @bitCast(bcd)));
                        }

                        self.p.z = self.a_s.c == 0;
                        self.p.n = (self.a_s.c & 0x8000) > 0;
                    }

                    self.p.c = sub1.@"1" == 0 and sub2.@"1" == 0;
                    self.p.v = ((a ^ result) & ((65535 - b) ^ result) & 0x8000) > 0;
                }
            },

            .SEC => {
                self.p.c = true;
                self.cycle_counter += 6;
            },

            .SED => {
                self.p.d = true;
                self.cycle_counter += 6;
            },

            .SEI => {
                self.p.i = true;
                self.cycle_counter += 6;
            },

            .SEP => {
                self.p = @bitCast(@as(u8, @bitCast(self.p)) | @as(u8, @truncate(self.resolved_address)));
                if (self.p.x) {
                    self.x_s.hl.xh = 0;
                    self.y_s.hl.yh = 0;
                }
                self.cycle_counter += 6;
            },

            .STA => {
                if (self.p.m) {
                    self.write(self.resolved_address, self.a_s.hl.a);
                } else {
                    var addr = self.resolved_address;
                    self.write(addr, self.a_s.hl.a);
                    addr = self.nextResolvedAddress();
                    self.write(addr, self.a_s.hl.b);
                }
            },

            .STX => {
                if (self.p.x) {
                    self.write(self.resolved_address, self.x_s.hl.xl);
                } else {
                    var addr = self.resolved_address;
                    self.write(addr, self.x_s.hl.xl);
                    addr = self.nextResolvedAddress();
                    self.write(addr, self.x_s.hl.xh);
                }
            },

            .STY => {
                if (self.p.x) {
                    self.write(self.resolved_address, self.y_s.hl.yl);
                } else {
                    var addr = self.resolved_address;
                    self.write(addr, self.y_s.hl.yl);
                    addr = self.nextResolvedAddress();
                    self.write(addr, self.y_s.hl.yh);
                }
            },

            .STZ => {
                if (self.p.m) {
                    self.write(self.resolved_address, 0);
                } else {
                    var addr = self.resolved_address;
                    self.write(addr, 0);
                    addr = self.nextResolvedAddress();
                    self.write(addr, 0);
                }
            },

            .TAX => {
                if (self.p.x) {
                    self.x_s.hl.xl = self.a_s.hl.a;
                    self.p.z = self.x_s.hl.xl == 0;
                    self.p.n = (self.x_s.hl.xl & 0x80) > 0;
                } else {
                    self.x_s.x = self.a_s.c;
                    self.p.z = self.x_s.x == 0;
                    self.p.n = (self.x_s.x & 0x8000) > 0;
                }
                self.cycle_counter += 6;
            },

            .TAY => {
                if (self.p.x) {
                    self.y_s.hl.yl = self.a_s.hl.a;
                    self.p.z = self.y_s.hl.yl == 0;
                    self.p.n = (self.y_s.hl.yl & 0x80) > 0;
                } else {
                    self.y_s.y = self.a_s.c;
                    self.p.z = self.y_s.y == 0;
                    self.p.n = (self.y_s.y & 0x8000) > 0;
                }
                self.cycle_counter += 6;
            },

            .TSX => {
                if (self.p.x) {
                    self.x_s.hl.xl = self.sp_s.hl.sl;
                    self.x_s.hl.xh = if (self.e) 1 else 0;
                    self.p.z = self.x_s.hl.xl == 0;
                    self.p.n = (self.x_s.hl.xl & 0x80) > 0;
                } else {
                    self.x_s.hl.xl = self.sp_s.hl.sl;
                    self.x_s.hl.xh = self.sp_s.hl.sh;
                    self.p.z = self.x_s.x == 0;
                    self.p.n = (self.x_s.x & 0x8000) > 0;
                }
                self.cycle_counter += 6;
            },

            .TXA => {
                if (self.p.m) {
                    self.a_s.hl.a = self.x_s.hl.xl;
                    self.p.z = self.a_s.hl.a == 0;
                    self.p.n = (self.a_s.hl.a & 0x80) > 0;
                } else {
                    self.a_s.c = self.x_s.x;
                    self.p.z = self.a_s.c == 0;
                    self.p.n = (self.a_s.c & 0x8000) > 0;
                }
                self.cycle_counter += 6;
            },

            .TXY => {
                if (self.p.x) {
                    self.y_s.hl.yl = self.x_s.hl.xl;
                    self.p.z = self.y_s.hl.yl == 0;
                    self.p.n = (self.y_s.hl.yl & 0x80) > 0;
                } else {
                    self.y_s.y = self.x_s.x;
                    self.p.z = self.y_s.y == 0;
                    self.p.n = (self.y_s.y & 0x8000) > 0;
                }
                self.cycle_counter += 6;
            },

            .TYA => {
                if (self.p.m) {
                    self.a_s.hl.a = self.y_s.hl.yl;
                    self.p.z = self.a_s.hl.a == 0;
                    self.p.n = (self.a_s.hl.a & 0x80) > 0;
                } else {
                    self.a_s.c = self.y_s.y;
                    self.p.z = self.a_s.c == 0;
                    self.p.n = (self.a_s.c & 0x8000) > 0;
                }
                self.cycle_counter += 6;
            },

            .TYX => {
                if (self.p.x) {
                    self.x_s.hl.xl = self.y_s.hl.yl;
                    self.p.z = self.x_s.hl.xl == 0;
                    self.p.n = (self.x_s.hl.xl & 0x80) > 0;
                } else {
                    self.x_s.x = self.y_s.y;
                    self.p.z = self.x_s.x == 0;
                    self.p.n = (self.x_s.x & 0x8000) > 0;
                }
                self.cycle_counter += 6;
            },

            .TXS => {
                self.sp_s.hl.sl = self.x_s.hl.xl;
                self.sp_s.hl.sh = self.x_s.hl.xh;
                self.cycle_counter += 6;
            },

            .TCD => {
                self.d_s.d = self.a_s.c;
                self.p.z = self.d_s.d == 0;
                self.p.n = (self.d_s.d & 0x8000) > 0;
                self.cycle_counter += 6;
            },

            .TCS => {
                self.sp_s.s = self.a_s.c;
                self.cycle_counter += 6;
            },

            .TDC => {
                self.a_s.c = self.d_s.d;
                self.p.z = self.a_s.c == 0;
                self.p.n = (self.a_s.c & 0x8000) > 0;
                self.cycle_counter += 6;
            },

            .TSC => {
                self.a_s.c = self.sp_s.s;
                self.p.z = self.a_s.c == 0;
                self.p.n = (self.a_s.c & 0x8000) > 0;
                self.cycle_counter += 6;
            },

            .TRB => {
                if (self.p.m) {
                    const v = self.read(self.resolved_address);
                    self.p.z = (self.a_s.hl.a & v) == 0;
                    self.cycle_counter += 6;
                    self.write(self.resolved_address, @truncate(v & ~self.a_s.hl.a));
                } else {
                    const addr1 = self.resolved_address;
                    const addr2 = self.nextResolvedAddress();
                    var v: u16 = self.read(addr1);
                    v |= @as(u16, self.read(addr2)) << 8;
                    self.p.z = (self.a_s.c & v) == 0;
                    self.cycle_counter += 6;
                    self.write(addr1, @truncate(v & ~self.a_s.c));
                    self.write(addr2, @truncate((v & ~self.a_s.c) >> 8));
                }
            },

            .TSB => {
                if (self.p.m) {
                    const v = self.read(self.resolved_address);
                    self.p.z = (self.a_s.hl.a & v) == 0;
                    self.cycle_counter += 6;
                    self.write(self.resolved_address, @truncate(v | self.a_s.hl.a));
                } else {
                    const addr1 = self.resolved_address;
                    const addr2 = self.nextResolvedAddress();
                    var v: u16 = self.read(addr1);
                    v |= @as(u16, self.read(addr2)) << 8;
                    self.p.z = (self.a_s.c & v) == 0;
                    self.cycle_counter += 6;
                    self.write(addr1, @truncate(v | self.a_s.c));
                    self.write(addr2, @truncate((v | self.a_s.c) >> 8));
                }
            },

            .XBA => {
                const a = self.a_s.hl.a;
                self.a_s.hl.a = self.a_s.hl.b;
                self.a_s.hl.b = a;
                self.p.z = self.a_s.hl.a == 0;
                self.p.n = (self.a_s.hl.a & 0x80) > 0;
                self.cycle_counter += 12;
            },

            .XCE => {
                const e = self.e;
                self.e = self.p.c;
                self.p.c = e;
                self.cycle_counter += 6;
            },

            .STP => {
                self.state = .stop;
                self.cycle_counter += 12;
            },

            .WAI => {
                self.state = .wait;
                self.cycle_counter += 12;
            },

            .WDM => {},
            .NOP => self.cycle_counter += 6,
        }

        if (self.e) {
            self.p.m = true;
            self.p.x = true;
            self.x_s.hl.xh = 0;
            self.y_s.hl.yh = 0;
            self.sp_s.hl.sh = 1;
        }
    }

    pub fn reset(self: *CPU) void {
        self.cycle_counter = 0;
        self.state = .normal;
        self.halt = false;
        self.irq_requested = false;
        self.nmi_requested = false;
        self.nmi_occurred = false;
        self.e = true;
        self.p.m = true;
        self.p.x = true;
        self.x_s.hl.xh = 0;
        self.y_s.hl.yh = 0;
        self.sp_s.hl.sh = 1;
        self.db = 0;
        self.irq(.reset);
    }

    pub fn serialize(self: *const CPU, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);
        c.mpack_write_cstr(pack, "cycle_counter");
        c.mpack_write_u32(pack, self.cycle_counter);
        c.mpack_write_cstr(pack, "state");
        c.mpack_write_u8(pack, @intFromEnum(self.state));
        c.mpack_write_cstr(pack, "irq_requested");
        c.mpack_write_bool(pack, self.irq_requested);
        c.mpack_write_cstr(pack, "nmi_requested");
        c.mpack_write_bool(pack, self.nmi_requested);
        c.mpack_write_cstr(pack, "nmi_occurred");
        c.mpack_write_bool(pack, self.nmi_occurred);
        c.mpack_write_cstr(pack, "halt");
        c.mpack_write_bool(pack, self.halt);
        c.mpack_write_cstr(pack, "resolved_address");
        c.mpack_write_u32(pack, self.resolved_address);
        c.mpack_write_cstr(pack, "resolved_mask");
        c.mpack_write_u32(pack, self.resolved_mask);
        c.mpack_write_cstr(pack, "pc");
        c.mpack_write_u16(pack, self.pc_s.pc);
        c.mpack_write_cstr(pack, "sp");
        c.mpack_write_u16(pack, self.sp_s.s);
        c.mpack_write_cstr(pack, "a");
        c.mpack_write_u16(pack, self.a_s.c);
        c.mpack_write_cstr(pack, "x");
        c.mpack_write_u16(pack, self.x_s.x);
        c.mpack_write_cstr(pack, "y");
        c.mpack_write_u16(pack, self.y_s.y);
        c.mpack_write_cstr(pack, "d");
        c.mpack_write_u16(pack, self.d_s.d);
        c.mpack_write_cstr(pack, "db");
        c.mpack_write_u8(pack, self.db);
        c.mpack_write_cstr(pack, "pb");
        c.mpack_write_u8(pack, self.pb);
        c.mpack_write_cstr(pack, "e");
        c.mpack_write_bool(pack, self.e);
        c.mpack_write_cstr(pack, "p");
        c.mpack_write_u8(pack, @as(u8, @bitCast(self.p)));
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *CPU, pack: c.mpack_node_t) void {
        self.cycle_counter = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "cycle_counter"));
        self.state = @enumFromInt(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "state")));
        self.irq_requested = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "irq_requested"));
        self.nmi_requested = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "nmi_requested"));
        self.nmi_occurred = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "nmi_occurred"));
        self.halt = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "halt"));
        self.resolved_address = @truncate(c.mpack_node_u32(c.mpack_node_map_cstr(pack, "resolved_address")));
        self.resolved_mask = @truncate(c.mpack_node_u32(c.mpack_node_map_cstr(pack, "resolved_mask")));
        self.pc_s.pc = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "pc"));
        self.sp_s.s = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "sp"));
        self.a_s.c = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "a"));
        self.x_s.x = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "x"));
        self.y_s.y = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "y"));
        self.d_s.d = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "d"));
        self.db = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "db"));
        self.pb = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "pb"));
        self.e = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "e"));
        self.p = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "p")));
    }
};

const BufferMapper = struct {
    data: [0x1000000]u8 = [_]u8{0} ** 0x1000000,

    pub fn read(ctx: *anyopaque, address: u24) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return self.data[address];
    }

    pub fn write(ctx: *anyopaque, address: u24, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.data[address] = value;
    }

    pub fn deinit(ctx: *anyopaque) void {
        _ = ctx;
    }

    pub fn memory(self: *@This()) Memory(u24, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinit,
            },
        };
    }
};

var memory: BufferMapper = .{};
