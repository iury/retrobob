const std = @import("std");
const IO = @import("io.zig").IO;
const Memory = @import("../../memory.zig").Memory;
const Proxy = @import("../../proxy.zig").Proxy;

const Opcode = packed struct {
    z: u3,
    y: packed union {
        y: u3,
        pq: packed struct {
            q: u1,
            p: u2,
        },
    },
    x: u2,
};

const Operand = union(enum) {
    R: enum(u8) { b = 0, c, d, e, h, l, hl, a },
    RP: enum(u2) { bc = 0, de, hl, sp },
    RP2: enum(u2) { bc = 0, de, hl, af },
    CC: enum(u2) { nz = 0, z, nc, c },
    ALU: enum(u8) { add = 0, adc, sub, sbc, @"and", xor, @"or", cp },
    ROT: enum(u8) { rlc = 0, rrc, rl, rr, sla, sra, swap, srl },
};

const CPUMode = enum { normal, switching, stop, halt, halt_bug, hang };

pub const CPU = struct {
    cycle_counter: u16 = 0,
    mode: CPUMode = .normal,
    double_speed: Proxy(bool),

    pc: u16 = 0x100,
    sp: u16 = 0xfffe,
    ime: bool = false,
    ei_pending: bool = false,

    af: packed struct {
        f: packed struct {
            unused: u4,
            c: bool,
            h: bool,
            n: bool,
            z: bool,
        },
        a: u8,
    } = @bitCast(@as(u16, 0x1180)),

    bc: packed struct {
        c: u8,
        b: u8,
    } = @bitCast(@as(u16, 0)),

    de: packed struct {
        e: u8,
        d: u8,
    } = @bitCast(@as(u16, 0)),

    hl: packed struct {
        l: u8,
        h: u8,
    } = @bitCast(@as(u16, 0)),

    memory: Memory(u16, u8),

    pub inline fn read(self: *CPU, address: u16) u8 {
        return self.memory.read(address);
    }

    pub inline fn write(self: *CPU, address: u16, value: u8) void {
        self.memory.write(address, value);
    }

    pub inline fn readIO(self: *CPU, io: IO) u8 {
        return self.memory.read(@intFromEnum(io));
    }

    pub inline fn writeIO(self: *CPU, io: IO, value: u8) void {
        self.memory.write(@intFromEnum(io), value);
    }

    fn fetch(self: *CPU) u8 {
        const v = self.read(self.pc);
        self.pc +%= 1;
        return v;
    }

    fn stop(self: *CPU) u16 {
        if ((self.readIO(.KEY1) & 1) > 0) {
            self.mode = .switching;
            return 32749;
        } else {
            self.mode = .stop;
            return 0;
        }
    }

    fn call(self: *CPU, address: u16) void {
        self.sp -%= 1;
        self.write(self.sp, @truncate(self.pc >> 8));
        self.sp -%= 1;
        self.write(self.sp, @truncate(self.pc & 0xff));
        self.pc = address;
    }

    fn ret(self: *CPU) void {
        var nn: u16 = self.read(self.sp);
        self.sp +%= 1;
        nn |= @as(u16, self.read(self.sp)) << 8;
        self.sp +%= 1;
        self.pc = nn;
    }

    pub fn process(self: *CPU) void {
        const log: bool = false;

        self.cycle_counter -|= 1;
        if (self.cycle_counter > 0) return;

        if (self.mode == .switching) {
            self.mode = .normal;
            const key1 = self.readIO(.KEY1) & 0x80;
            if (key1 == 0) {
                self.writeIO(.KEY1, 0xfe);
                self.double_speed.set(true);
                if (log) std.debug.print("switched to double speed.\n", .{});
            } else {
                self.writeIO(.KEY1, 0x7e);
                self.double_speed.set(false);
                if (log) std.debug.print("switched to normal speed.\n", .{});
            }
        }

        const iflags = self.readIO(.IF) & 0x1f;
        const ie = self.readIO(.IE) & 0x1f;

        if (self.mode == .halt) {
            if ((iflags & ie) > 0) self.mode = .normal;
        }

        if (self.mode == .stop) {
            if ((iflags & 0x10) > 0) self.mode = .normal;
        }

        if (self.mode != .normal and self.mode != .halt_bug) return;

        // vblank
        if ((iflags & ie & 0x01) > 0) {
            if (log) std.debug.print("vblank interrupt...\n", .{});
            if (self.ime) {
                self.ime = false;
                self.writeIO(.IF, iflags & ~@as(u8, 0x01));
                self.cycle_counter = 5;
                self.call(0x40);
                if (log) std.debug.print("vblank handled.\n", .{});
                return;
            }
        }

        // lcd
        if ((iflags & ie & 0x02) > 0) {
            if (log) std.debug.print("lcd interrupt...\n", .{});
            if (self.ime) {
                self.ime = false;
                self.writeIO(.IF, iflags & ~@as(u8, 0x02));
                self.cycle_counter = 5;
                self.call(0x48);
                if (log) std.debug.print("lcd handled.\n", .{});
                return;
            }
        }

        // timer
        if ((iflags & ie & 0x04) > 0) {
            if (log) std.debug.print("timer interrupt...\n", .{});
            if (self.ime) {
                self.ime = false;
                self.writeIO(.IF, iflags & ~@as(u8, 0x04));
                self.cycle_counter = 5;
                self.call(0x50);
                if (log) std.debug.print("timer handled.\n", .{});
                return;
            }
        }

        // serial
        if ((iflags & ie & 0x08) > 0) {
            if (log) std.debug.print("serial interrupt...\n", .{});
            if (self.ime) {
                self.ime = false;
                self.writeIO(.IF, iflags & ~@as(u8, 0x08));
                self.cycle_counter = 5;
                self.call(0x58);
                if (log) std.debug.print("serial handled.\n", .{});
                return;
            }
        }

        // joypad
        if ((iflags & ie & 0x10) > 0) {
            if (log) std.debug.print("joypad interrupt...\n", .{});
            if (self.ime) {
                self.ime = false;
                self.writeIO(.IF, iflags & ~@as(u8, 0x10));
                self.cycle_counter = 5;
                self.call(0x60);
                if (log) std.debug.print("joypad handled.\n", .{});
                return;
            }
        }

        if (self.ei_pending) {
            self.ei_pending = false;
            self.ime = true;
        }

        const opcode: Opcode = @bitCast(self.fetch());

        if (self.mode == .halt_bug) {
            self.mode = .normal;
            self.pc -%= 1;
        }

        self.cycle_counter = switch (opcode.x) {
            0 => blk: {
                switch (opcode.z) {
                    0 => {
                        switch (opcode.y.y) {
                            0 => {
                                // NOP
                                if (log) std.debug.print("NOP", .{});
                                break :blk 1;
                            },
                            1 => {
                                // LD (nn), SP
                                var nn: u16 = self.fetch();
                                nn |= @as(u16, self.fetch()) << 8;
                                self.write(nn, @as(u8, @truncate(self.sp & 0xff)));
                                self.write(nn +% 1, @as(u8, @truncate(self.sp >> 8)));
                                if (log) std.debug.print("LD ({X:0>4}), SP", .{nn});
                                break :blk 5;
                            },
                            2 => {
                                // STOP
                                if (log) std.debug.print("STOP", .{});
                                break :blk self.stop();
                            },
                            3 => {
                                // JR d
                                const d: u16 = @bitCast(@as(i16, @as(i8, @bitCast(self.fetch()))));
                                self.pc +%= d;
                                if (log) std.debug.print("JR {d}", .{@as(i8, @truncate(@as(i16, @bitCast(d))))});
                                break :blk 3;
                            },
                            4...7 => {
                                // JR cc[y-4], d
                                const d: u16 = @bitCast(@as(i16, @as(i8, @bitCast(self.fetch()))));
                                const cc: Operand = .{ .CC = @enumFromInt(opcode.y.y - 4) };
                                const take = switch (cc.CC) {
                                    .nz => !self.af.f.z,
                                    .z => self.af.f.z,
                                    .nc => !self.af.f.c,
                                    .c => self.af.f.c,
                                };
                                if (take) self.pc +%= d;
                                if (log) std.debug.print("JR {s}, {d}", .{ @tagName(cc.CC), @as(i8, @truncate(@as(i16, @bitCast(d)))) });
                                break :blk if (take) 3 else 2;
                            },
                        }
                    },
                    1 => {
                        switch (opcode.y.pq.q) {
                            0 => {
                                // LD rp[p], nn
                                var nn: u16 = self.fetch();
                                nn |= @as(u16, self.fetch()) << 8;
                                const rp: Operand = .{ .RP = @enumFromInt(opcode.y.pq.p) };
                                switch (rp.RP) {
                                    .bc => self.bc = @bitCast(nn),
                                    .de => self.de = @bitCast(nn),
                                    .hl => self.hl = @bitCast(nn),
                                    .sp => self.sp = @bitCast(nn),
                                }
                                if (log) std.debug.print("LD {s}, {X:0>4}", .{ @tagName(rp.RP), nn });
                                break :blk 3;
                            },
                            1 => {
                                // ADD HL, rp[p]
                                const rp: Operand = .{ .RP = @enumFromInt(opcode.y.pq.p) };
                                const a: u16 = @bitCast(self.hl);
                                const b: u16 = switch (rp.RP) {
                                    .bc => @bitCast(self.bc),
                                    .de => @bitCast(self.de),
                                    .hl => @bitCast(self.hl),
                                    .sp => @bitCast(self.sp),
                                };
                                const v = @addWithOverflow(a, b);
                                self.hl = @bitCast(v.@"0");
                                self.af.f.n = false;
                                self.af.f.h = (a ^ b ^ v.@"0") & 0x1000 != 0;
                                self.af.f.c = v.@"1" == 1;
                                if (log) std.debug.print("ADD HL, {s}", .{@tagName(rp.RP)});
                                break :blk 2;
                            },
                        }
                    },
                    2 => {
                        switch (opcode.y.pq.q) {
                            0 => {
                                switch (opcode.y.pq.p) {
                                    0 => {
                                        // LD (BC), A
                                        self.write(@bitCast(self.bc), self.af.a);
                                        if (log) std.debug.print("LD (BC), A", .{});
                                        break :blk 2;
                                    },
                                    1 => {
                                        // LD (DE), A
                                        self.write(@bitCast(self.de), self.af.a);
                                        if (log) std.debug.print("LD (DE), A", .{});
                                        break :blk 2;
                                    },
                                    2 => {
                                        // LD (HL+), A
                                        self.write(@bitCast(self.hl), self.af.a);
                                        self.hl = @bitCast(@as(u16, @bitCast(self.hl)) +% 1);
                                        if (log) std.debug.print("LD (HL+), A", .{});
                                        break :blk 2;
                                    },
                                    3 => {
                                        // LD (HL-), A
                                        self.write(@bitCast(self.hl), self.af.a);
                                        self.hl = @bitCast(@as(u16, @bitCast(self.hl)) -% 1);
                                        if (log) std.debug.print("LD (HL-), A", .{});
                                        break :blk 2;
                                    },
                                }
                            },
                            1 => {
                                switch (opcode.y.pq.p) {
                                    0 => {
                                        // LD A, (BC)
                                        self.af.a = self.read(@bitCast(self.bc));
                                        if (log) std.debug.print("LD A, (BC)", .{});
                                        break :blk 2;
                                    },
                                    1 => {
                                        // LD A, (DE)
                                        self.af.a = self.read(@bitCast(self.de));
                                        if (log) std.debug.print("LD A, (DE)", .{});
                                        break :blk 2;
                                    },
                                    2 => {
                                        // LD A, (HL+)
                                        self.af.a = self.read(@bitCast(self.hl));
                                        self.hl = @bitCast(@as(u16, @bitCast(self.hl)) +% 1);
                                        if (log) std.debug.print("LD A, (HL+)", .{});
                                        break :blk 2;
                                    },
                                    3 => {
                                        // LD A, (HL-)
                                        self.af.a = self.read(@bitCast(self.hl));
                                        self.hl = @bitCast(@as(u16, @bitCast(self.hl)) -% 1);
                                        if (log) std.debug.print("LD A, (HL-)", .{});
                                        break :blk 2;
                                    },
                                }
                            },
                        }
                    },
                    3 => {
                        switch (opcode.y.pq.q) {
                            0 => {
                                // INC rp[p]
                                const rp: Operand = .{ .RP = @enumFromInt(opcode.y.pq.p) };
                                switch (rp.RP) {
                                    .bc => self.bc = @bitCast(@as(u16, @bitCast(self.bc)) +% 1),
                                    .de => self.de = @bitCast(@as(u16, @bitCast(self.de)) +% 1),
                                    .hl => self.hl = @bitCast(@as(u16, @bitCast(self.hl)) +% 1),
                                    .sp => self.sp = @bitCast(@as(u16, @bitCast(self.sp)) +% 1),
                                }
                                if (log) std.debug.print("INC {s}", .{@tagName(rp.RP)});
                                break :blk 2;
                            },
                            1 => {
                                // DEC rp[p]
                                const rp: Operand = .{ .RP = @enumFromInt(opcode.y.pq.p) };
                                switch (rp.RP) {
                                    .bc => self.bc = @bitCast(@as(u16, @bitCast(self.bc)) -% 1),
                                    .de => self.de = @bitCast(@as(u16, @bitCast(self.de)) -% 1),
                                    .hl => self.hl = @bitCast(@as(u16, @bitCast(self.hl)) -% 1),
                                    .sp => self.sp = @bitCast(@as(u16, @bitCast(self.sp)) -% 1),
                                }
                                if (log) std.debug.print("DEC {s}", .{@tagName(rp.RP)});
                                break :blk 2;
                            },
                        }
                    },
                    4 => {
                        // INC r[y]
                        const r: Operand = .{ .R = @enumFromInt(opcode.y.y) };
                        const hl = switch (r.R) {
                            .hl => true,
                            else => false,
                        };
                        const a = switch (r.R) {
                            .a => self.af.a,
                            .b => self.bc.b,
                            .c => self.bc.c,
                            .d => self.de.d,
                            .e => self.de.e,
                            .h => self.hl.h,
                            .l => self.hl.l,
                            .hl => self.read(@bitCast(self.hl)),
                        };
                        const v = a +% 1;
                        switch (r.R) {
                            .a => self.af.a = v,
                            .b => self.bc.b = v,
                            .c => self.bc.c = v,
                            .d => self.de.d = v,
                            .e => self.de.e = v,
                            .h => self.hl.h = v,
                            .l => self.hl.l = v,
                            .hl => self.write(@bitCast(self.hl), v),
                        }
                        self.af.f.n = false;
                        self.af.f.z = v == 0;
                        self.af.f.h = (a ^ 1 ^ v) & 0x10 != 0;
                        if (log) std.debug.print("INC {s}", .{@tagName(r.R)});
                        break :blk if (hl) 3 else 1;
                    },
                    5 => {
                        // 	DEC r[y]
                        const r: Operand = .{ .R = @enumFromInt(opcode.y.y) };
                        const hl = switch (r.R) {
                            .hl => true,
                            else => false,
                        };
                        const a = switch (r.R) {
                            .a => self.af.a,
                            .b => self.bc.b,
                            .c => self.bc.c,
                            .d => self.de.d,
                            .e => self.de.e,
                            .h => self.hl.h,
                            .l => self.hl.l,
                            .hl => self.read(@bitCast(self.hl)),
                        };
                        const v = a -% 1;
                        switch (r.R) {
                            .a => self.af.a = v,
                            .b => self.bc.b = v,
                            .c => self.bc.c = v,
                            .d => self.de.d = v,
                            .e => self.de.e = v,
                            .h => self.hl.h = v,
                            .l => self.hl.l = v,
                            .hl => self.write(@bitCast(self.hl), v),
                        }
                        self.af.f.n = true;
                        self.af.f.z = v == 0;
                        self.af.f.h = (a ^ 1 ^ v) & 0x10 != 0;
                        if (log) std.debug.print("DEC {s}", .{@tagName(r.R)});
                        break :blk if (hl) 3 else 1;
                    },
                    6 => {
                        // LD r[y], n
                        const n = self.fetch();
                        const r: Operand = .{ .R = @enumFromInt(opcode.y.y) };
                        const hl = switch (r.R) {
                            .hl => true,
                            else => false,
                        };
                        switch (r.R) {
                            .a => self.af.a = n,
                            .b => self.bc.b = n,
                            .c => self.bc.c = n,
                            .d => self.de.d = n,
                            .e => self.de.e = n,
                            .h => self.hl.h = n,
                            .l => self.hl.l = n,
                            .hl => self.write(@bitCast(self.hl), n),
                        }
                        if (log) std.debug.print("LD {s}, {X:0>2}", .{ @tagName(r.R), n });
                        break :blk if (hl) 3 else 2;
                    },
                    7 => {
                        switch (opcode.y.y) {
                            0 => {
                                // RLCA
                                const v = @shlWithOverflow(self.af.a, 1);
                                self.af.a = v.@"0" | v.@"1";
                                self.af.f.c = v.@"1" == 1;
                                self.af.f.z = false;
                                self.af.f.n = false;
                                self.af.f.h = false;
                                if (log) std.debug.print("RLCA", .{});
                                break :blk 1;
                            },
                            1 => {
                                // RRCA
                                const c: u8 = if ((self.af.a & 0x1) > 0) 0x80 else 0;
                                self.af.f.c = c > 0;
                                self.af.a = (self.af.a >> 1) | c;
                                self.af.f.z = false;
                                self.af.f.n = false;
                                self.af.f.h = false;
                                if (log) std.debug.print("RRCA", .{});
                                break :blk 1;
                            },
                            2 => {
                                // RLA
                                const c: u8 = if (self.af.f.c) 1 else 0;
                                const v = @shlWithOverflow(self.af.a, 1);
                                self.af.a = v.@"0" | c;
                                self.af.f.c = v.@"1" == 1;
                                self.af.f.z = false;
                                self.af.f.n = false;
                                self.af.f.h = false;
                                if (log) std.debug.print("RLA", .{});
                                break :blk 1;
                            },
                            3 => {
                                // RRA
                                const c: u8 = if (self.af.f.c) 0x80 else 0;
                                self.af.f.c = self.af.a & 0x1 > 0;
                                self.af.a = (self.af.a >> 1) | c;
                                self.af.f.z = false;
                                self.af.f.n = false;
                                self.af.f.h = false;
                                if (log) std.debug.print("RRA", .{});
                                break :blk 1;
                            },
                            4 => {
                                // DAA
                                var v: u8 = 0;
                                if (self.af.f.h or (!self.af.f.n and (self.af.a & 0xf) > 9)) {
                                    v = 6;
                                }
                                if (self.af.f.c or (!self.af.f.n and (self.af.a > 0x99))) {
                                    v |= 0x60;
                                    self.af.f.c = true;
                                }
                                self.af.a +%= if (self.af.f.n) ~v +% 1 else v;
                                self.af.f.z = self.af.a == 0;
                                self.af.f.h = false;
                                if (log) std.debug.print("DAA", .{});
                                break :blk 1;
                            },
                            5 => {
                                // CPL
                                self.af.a = ~self.af.a;
                                self.af.f.n = true;
                                self.af.f.h = true;
                                if (log) std.debug.print("CPL", .{});
                                break :blk 1;
                            },
                            6 => {
                                // SCF
                                self.af.f.c = true;
                                self.af.f.n = false;
                                self.af.f.h = false;
                                if (log) std.debug.print("SCF", .{});
                                break :blk 1;
                            },
                            7 => {
                                // CCF
                                self.af.f.c = !self.af.f.c;
                                self.af.f.n = false;
                                self.af.f.h = false;
                                if (log) std.debug.print("CCF", .{});
                                break :blk 1;
                            },
                        }
                    },
                }
            },
            1 => blk: {
                if (opcode.z == @as(u3, 6) and opcode.y.y == @as(u3, 6)) {
                    // HALT
                    if (self.ime) {
                        self.mode = .halt;
                    } else {
                        if ((iflags & ie) > 0) {
                            self.mode = .halt_bug;
                        } else {
                            self.mode = .halt;
                        }
                    }
                    if (log) std.debug.print("HALT", .{});
                    break :blk 0;
                } else {
                    // LD r[y], r[z]
                    const r: Operand = .{ .R = @enumFromInt(opcode.y.y) };
                    const rz: Operand = .{ .R = @enumFromInt(opcode.z) };
                    const hl1 = switch (r.R) {
                        .hl => true,
                        else => false,
                    };
                    const hl2 = switch (rz.R) {
                        .hl => true,
                        else => false,
                    };
                    const n = switch (rz.R) {
                        .a => self.af.a,
                        .b => self.bc.b,
                        .c => self.bc.c,
                        .d => self.de.d,
                        .e => self.de.e,
                        .h => self.hl.h,
                        .l => self.hl.l,
                        .hl => self.read(@bitCast(self.hl)),
                    };
                    switch (r.R) {
                        .a => self.af.a = n,
                        .b => self.bc.b = n,
                        .c => self.bc.c = n,
                        .d => self.de.d = n,
                        .e => self.de.e = n,
                        .h => self.hl.h = n,
                        .l => self.hl.l = n,
                        .hl => self.write(@bitCast(self.hl), n),
                    }
                    if (log) std.debug.print("LD {s} {s}", .{ @tagName(r.R), @tagName(rz.R) });
                    break :blk if (hl1 or hl2) 2 else 1;
                }
            },
            2 => blk: {
                // alu[y] r[z]
                const alu: Operand = .{ .ALU = @enumFromInt(opcode.y.y) };
                const r: Operand = .{ .R = @enumFromInt(opcode.z) };
                const hl = switch (r.R) {
                    .hl => true,
                    else => false,
                };

                const b: u8 = switch (r.R) {
                    .a => self.af.a,
                    .b => self.bc.b,
                    .c => self.bc.c,
                    .d => self.de.d,
                    .e => self.de.e,
                    .h => self.hl.h,
                    .l => self.hl.l,
                    .hl => self.read(@bitCast(self.hl)),
                };

                switch (alu.ALU) {
                    .add => {
                        const a = self.af.a;
                        const v = @addWithOverflow(a, b);
                        self.af.a = v.@"0";
                        self.af.f.n = false;
                        self.af.f.z = v.@"0" == 0;
                        self.af.f.c = v.@"1" == 1;
                        self.af.f.h = (a ^ b ^ v.@"0") & 0x10 != 0;
                        if (log) std.debug.print("ADD {s}", .{@tagName(r.R)});
                    },
                    .adc => {
                        const a = self.af.a;
                        const c = @as(u8, if (self.af.f.c) 1 else 0);
                        const vp = @addWithOverflow(a, b);
                        const v = @addWithOverflow(vp.@"0", c);
                        self.af.a = v.@"0";
                        self.af.f.n = false;
                        self.af.f.z = v.@"0" == 0;
                        self.af.f.c = v.@"1" == 1 or vp.@"1" == 1;
                        self.af.f.h = (a ^ b ^ c ^ v.@"0") & 0x10 != 0;
                        if (log) std.debug.print("ADC {s}", .{@tagName(r.R)});
                    },
                    .sub => {
                        const a = self.af.a;
                        const v = @subWithOverflow(a, b);
                        self.af.a = v.@"0";
                        self.af.f.n = true;
                        self.af.f.z = v.@"0" == 0;
                        self.af.f.c = v.@"1" == 1;
                        self.af.f.h = (a ^ b ^ v.@"0") & 0x10 != 0;
                        if (log) std.debug.print("SUB {s}", .{@tagName(r.R)});
                    },
                    .sbc => {
                        const a = self.af.a;
                        const c = @as(u8, if (self.af.f.c) 1 else 0);
                        const vp = @subWithOverflow(a, b);
                        const v = @subWithOverflow(vp.@"0", c);
                        self.af.a = v.@"0";
                        self.af.f.n = true;
                        self.af.f.z = v.@"0" == 0;
                        self.af.f.c = v.@"1" == 1 or vp.@"1" == 1;
                        self.af.f.h = (a ^ b ^ c ^ v.@"0") & 0x10 != 0;
                        if (log) std.debug.print("SBC {s}", .{@tagName(r.R)});
                    },
                    .@"and" => {
                        self.af.a &= b;
                        self.af.f.z = self.af.a == 0;
                        self.af.f.h = true;
                        self.af.f.n = false;
                        self.af.f.c = false;
                        if (log) std.debug.print("AND {s}", .{@tagName(r.R)});
                    },
                    .xor => {
                        self.af.a ^= b;
                        self.af.f.z = self.af.a == 0;
                        self.af.f.h = false;
                        self.af.f.n = false;
                        self.af.f.c = false;
                        if (log) std.debug.print("XOR {s}", .{@tagName(r.R)});
                    },
                    .@"or" => {
                        self.af.a |= b;
                        self.af.f.z = self.af.a == 0;
                        self.af.f.h = false;
                        self.af.f.n = false;
                        self.af.f.c = false;
                        if (log) std.debug.print("OR {s}", .{@tagName(r.R)});
                    },
                    .cp => {
                        const a = self.af.a;
                        const v = @subWithOverflow(a, b);
                        self.af.f.n = true;
                        self.af.f.z = v.@"0" == 0;
                        self.af.f.c = v.@"1" == 1;
                        self.af.f.h = (a ^ b ^ v.@"0") & 0x10 != 0;
                        if (log) std.debug.print("CP {s}", .{@tagName(r.R)});
                    },
                }
                break :blk if (hl) 2 else 1;
            },
            3 => blk: {
                switch (opcode.z) {
                    0 => {
                        switch (opcode.y.y) {
                            0...3 => {
                                // RET cc[y]
                                const cc: Operand = .{ .CC = @enumFromInt(opcode.y.y) };
                                const take = switch (cc.CC) {
                                    .nz => !self.af.f.z,
                                    .z => self.af.f.z,
                                    .nc => !self.af.f.c,
                                    .c => self.af.f.c,
                                };
                                if (take) self.ret();
                                if (log) std.debug.print("RET {s}", .{@tagName(cc.CC)});
                                break :blk if (take) 5 else 2;
                            },
                            4 => {
                                // LD (0xFF00 + n), A
                                const n: u16 = self.fetch();
                                self.write(0xff00 | n, self.af.a);
                                if (log) std.debug.print("LD (FF{X:0>2}), A", .{n});
                                break :blk 3;
                            },
                            5 => {
                                // ADD SP, d
                                const a: u8 = @truncate(self.sp & 0xff);
                                const b: u8 = self.fetch();
                                const v = @addWithOverflow(a, b);
                                self.sp +%= @bitCast(@as(i16, @as(i8, @bitCast(b))));
                                self.af.f.z = false;
                                self.af.f.n = false;
                                self.af.f.c = v.@"1" == 1;
                                self.af.f.h = (a ^ b ^ v.@"0") & 0x10 != 0;
                                if (log) std.debug.print("ADD SP, {d}", .{@as(i8, @bitCast(b))});
                                break :blk 4;
                            },
                            6 => {
                                // LD A, (0xFF00 + n)
                                const n: u16 = self.fetch();
                                self.af.a = self.read(0xff00 | n);
                                if (log) std.debug.print("LD A, (FF{X:0>2})", .{n});
                                break :blk 3;
                            },
                            7 => {
                                // LD HL, SP+ d
                                const a: u8 = @truncate(self.sp & 0xff);
                                const b: u8 = self.fetch();
                                const v = @addWithOverflow(a, b);
                                self.hl = @bitCast(self.sp +% @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(b))))));
                                self.af.f.z = false;
                                self.af.f.n = false;
                                self.af.f.c = v.@"1" == 1;
                                self.af.f.h = (a ^ b ^ v.@"0") & 0x10 != 0;
                                if (log) std.debug.print("LD HL, SP+ {d}", .{@as(i8, @bitCast(b))});
                                break :blk 3;
                            },
                        }
                    },
                    1 => {
                        switch (opcode.y.pq.q) {
                            0 => {
                                // POP rp2[p]
                                const rp2: Operand = .{ .RP2 = @enumFromInt(opcode.y.pq.p) };
                                switch (rp2.RP2) {
                                    .bc => {
                                        self.bc.c = self.read(self.sp);
                                        self.sp +%= 1;
                                        self.bc.b = self.read(self.sp);
                                        self.sp +%= 1;
                                    },
                                    .de => {
                                        self.de.e = self.read(self.sp);
                                        self.sp +%= 1;
                                        self.de.d = self.read(self.sp);
                                        self.sp +%= 1;
                                    },
                                    .hl => {
                                        self.hl.l = self.read(self.sp);
                                        self.sp +%= 1;
                                        self.hl.h = self.read(self.sp);
                                        self.sp +%= 1;
                                    },
                                    .af => {
                                        self.af.f = @bitCast(self.read(self.sp) & 0xf0);
                                        self.sp +%= 1;
                                        self.af.a = self.read(self.sp);
                                        self.sp +%= 1;
                                    },
                                }
                                if (log) std.debug.print("POP {s}", .{@tagName(rp2.RP2)});
                                break :blk 3;
                            },
                            1 => {
                                switch (opcode.y.pq.p) {
                                    0 => {
                                        // RET
                                        self.ret();
                                        if (log) std.debug.print("RET", .{});
                                        break :blk 4;
                                    },
                                    1 => {
                                        // RETI
                                        self.ime = true;
                                        self.ret();
                                        if (log) std.debug.print("RETI", .{});
                                        break :blk 4;
                                    },
                                    2 => {
                                        // JP HL
                                        self.pc = @bitCast(self.hl);
                                        if (log) std.debug.print("JP HL", .{});
                                        break :blk 1;
                                    },
                                    3 => {
                                        // LD SP, HL
                                        self.sp = @bitCast(self.hl);
                                        if (log) std.debug.print("LD SP, HL", .{});
                                        break :blk 2;
                                    },
                                }
                            },
                        }
                    },
                    2 => {
                        switch (opcode.y.y) {
                            0...3 => {
                                // JP cc[y], nn
                                var nn: u16 = self.fetch();
                                nn |= @as(u16, self.fetch()) << 8;
                                const cc: Operand = .{ .CC = @enumFromInt(opcode.y.y) };
                                const take = switch (cc.CC) {
                                    .nz => !self.af.f.z,
                                    .z => self.af.f.z,
                                    .nc => !self.af.f.c,
                                    .c => self.af.f.c,
                                };
                                if (take) self.pc = nn;
                                if (log) std.debug.print("JP {s}, {X:0>4}", .{ @tagName(cc.CC), nn });
                                break :blk if (take) 4 else 3;
                            },
                            4 => {
                                // LD (0xFF00+C), A
                                self.write(0xff00 | @as(u16, self.bc.c), self.af.a);
                                if (log) std.debug.print("LD (ff+C), A", .{});
                                break :blk 2;
                            },
                            5 => {
                                // LD (nn), A
                                var nn: u16 = self.fetch();
                                nn |= @as(u16, self.fetch()) << 8;
                                self.write(nn, self.af.a);
                                if (log) std.debug.print("LD ({X:0>4}), A", .{nn});
                                break :blk 4;
                            },
                            6 => {
                                // LD A, (0xFF00+C)
                                self.af.a = self.read(0xff00 | @as(u16, self.bc.c));
                                if (log) std.debug.print("LD A, (ff+C)", .{});
                                break :blk 2;
                            },
                            7 => {
                                // LD A, (nn)
                                var nn: u16 = self.fetch();
                                nn |= @as(u16, self.fetch()) << 8;
                                self.af.a = self.read(nn);
                                if (log) std.debug.print("LD A, ({X:0>4})", .{nn});
                                break :blk 4;
                            },
                        }
                    },
                    3 => {
                        switch (opcode.y.y) {
                            0 => {
                                // JP nn
                                var nn: u16 = self.fetch();
                                nn |= @as(u16, self.fetch()) << 8;
                                self.pc = nn;
                                if (log) std.debug.print("JP {X:0>4}", .{nn});
                                break :blk 4;
                            },
                            1 => {
                                // (CB prefix)
                                const cb: Opcode = @bitCast(self.fetch());
                                const r: Operand = .{ .R = @enumFromInt(cb.z) };
                                const hl = switch (r.R) {
                                    .hl => true,
                                    else => false,
                                };
                                switch (cb.x) {
                                    0 => {
                                        // rot[y] r[z]
                                        const rot: Operand = .{ .ROT = @enumFromInt(cb.y.y) };
                                        switch (rot.ROT) {
                                            .rlc => {
                                                const v = switch (r.R) {
                                                    .a => inner: {
                                                        const v = @shlWithOverflow(self.af.a, 1);
                                                        self.af.a = v.@"0" | v.@"1";
                                                        break :inner v;
                                                    },
                                                    .b => inner: {
                                                        const v = @shlWithOverflow(self.bc.b, 1);
                                                        self.bc.b = v.@"0" | v.@"1";
                                                        break :inner v;
                                                    },
                                                    .c => inner: {
                                                        const v = @shlWithOverflow(self.bc.c, 1);
                                                        self.bc.c = v.@"0" | v.@"1";
                                                        break :inner v;
                                                    },
                                                    .d => inner: {
                                                        const v = @shlWithOverflow(self.de.d, 1);
                                                        self.de.d = v.@"0" | v.@"1";
                                                        break :inner v;
                                                    },
                                                    .e => inner: {
                                                        const v = @shlWithOverflow(self.de.e, 1);
                                                        self.de.e = v.@"0" | v.@"1";
                                                        break :inner v;
                                                    },
                                                    .h => inner: {
                                                        const v = @shlWithOverflow(self.hl.h, 1);
                                                        self.hl.h = v.@"0" | v.@"1";
                                                        break :inner v;
                                                    },
                                                    .l => inner: {
                                                        const v = @shlWithOverflow(self.hl.l, 1);
                                                        self.hl.l = v.@"0" | v.@"1";
                                                        break :inner v;
                                                    },
                                                    .hl => inner: {
                                                        const v = @shlWithOverflow(self.read(@bitCast(self.hl)), 1);
                                                        self.write(@bitCast(self.hl), v.@"0" | v.@"1");
                                                        break :inner v;
                                                    },
                                                };
                                                self.af.f.z = (v.@"0" | v.@"1") == 0;
                                                self.af.f.c = v.@"1" == 1;
                                                if (log) std.debug.print("RLC {s}", .{@tagName(r.R)});
                                            },
                                            .rrc => {
                                                switch (r.R) {
                                                    .a => {
                                                        const c: u8 = if ((self.af.a & 0x1) > 0) 0x80 else 0;
                                                        self.af.f.c = c > 0;
                                                        self.af.a = (self.af.a >> 1) | c;
                                                        self.af.f.z = self.af.a == 0;
                                                    },
                                                    .b => {
                                                        const c: u8 = if ((self.bc.b & 0x1) > 0) 0x80 else 0;
                                                        self.af.f.c = c > 0;
                                                        self.bc.b = (self.bc.b >> 1) | c;
                                                        self.af.f.z = self.bc.b == 0;
                                                    },
                                                    .c => {
                                                        const c: u8 = if ((self.bc.c & 0x1) > 0) 0x80 else 0;
                                                        self.af.f.c = c > 0;
                                                        self.bc.c = (self.bc.c >> 1) | c;
                                                        self.af.f.z = self.bc.c == 0;
                                                    },
                                                    .d => {
                                                        const c: u8 = if ((self.de.d & 0x1) > 0) 0x80 else 0;
                                                        self.af.f.c = c > 0;
                                                        self.de.d = (self.de.d >> 1) | c;
                                                        self.af.f.z = self.de.d == 0;
                                                    },
                                                    .e => {
                                                        const c: u8 = if ((self.de.e & 0x1) > 0) 0x80 else 0;
                                                        self.af.f.c = c > 0;
                                                        self.de.e = (self.de.e >> 1) | c;
                                                        self.af.f.z = self.de.e == 0;
                                                    },
                                                    .h => {
                                                        const c: u8 = if ((self.hl.h & 0x1) > 0) 0x80 else 0;
                                                        self.af.f.c = c > 0;
                                                        self.hl.h = (self.hl.h >> 1) | c;
                                                        self.af.f.z = self.hl.h == 0;
                                                    },
                                                    .l => {
                                                        const c: u8 = if ((self.hl.l & 0x1) > 0) 0x80 else 0;
                                                        self.af.f.c = c > 0;
                                                        self.hl.l = (self.hl.l >> 1) | c;
                                                        self.af.f.z = self.hl.l == 0;
                                                    },
                                                    .hl => {
                                                        var v = self.read(@bitCast(self.hl));
                                                        const c: u8 = if ((v & 0x1) > 0) 0x80 else 0;
                                                        self.af.f.c = c > 0;
                                                        v = (v >> 1) | c;
                                                        self.af.f.z = v == 0;
                                                        self.write(@bitCast(self.hl), v);
                                                    },
                                                }
                                                if (log) std.debug.print("RRC {s}", .{@tagName(r.R)});
                                            },
                                            .rl => {
                                                const c: u8 = if (self.af.f.c) 1 else 0;
                                                const v = switch (r.R) {
                                                    .a => inner: {
                                                        const v = @shlWithOverflow(self.af.a, 1);
                                                        self.af.a = v.@"0" | c;
                                                        break :inner v;
                                                    },
                                                    .b => inner: {
                                                        const v = @shlWithOverflow(self.bc.b, 1);
                                                        self.bc.b = v.@"0" | c;
                                                        break :inner v;
                                                    },
                                                    .c => inner: {
                                                        const v = @shlWithOverflow(self.bc.c, 1);
                                                        self.bc.c = v.@"0" | c;
                                                        break :inner v;
                                                    },
                                                    .d => inner: {
                                                        const v = @shlWithOverflow(self.de.d, 1);
                                                        self.de.d = v.@"0" | c;
                                                        break :inner v;
                                                    },
                                                    .e => inner: {
                                                        const v = @shlWithOverflow(self.de.e, 1);
                                                        self.de.e = v.@"0" | c;
                                                        break :inner v;
                                                    },
                                                    .h => inner: {
                                                        const v = @shlWithOverflow(self.hl.h, 1);
                                                        self.hl.h = v.@"0" | c;
                                                        break :inner v;
                                                    },
                                                    .l => inner: {
                                                        const v = @shlWithOverflow(self.hl.l, 1);
                                                        self.hl.l = v.@"0" | c;
                                                        break :inner v;
                                                    },
                                                    .hl => inner: {
                                                        const v = @shlWithOverflow(self.read(@bitCast(self.hl)), 1);
                                                        self.write(@bitCast(self.hl), v.@"0" | c);
                                                        break :inner v;
                                                    },
                                                };
                                                self.af.f.z = (v.@"0" | c) == 0;
                                                self.af.f.c = v.@"1" == 1;
                                                if (log) std.debug.print("RL {s}", .{@tagName(r.R)});
                                            },
                                            .rr => {
                                                const c: u8 = if (self.af.f.c) 0x80 else 0;
                                                switch (r.R) {
                                                    .a => {
                                                        self.af.f.c = (self.af.a & 1) > 0;
                                                        self.af.a = (self.af.a >> 1) | c;
                                                        self.af.f.z = self.af.a == 0;
                                                    },
                                                    .b => {
                                                        self.af.f.c = (self.bc.b & 1) > 0;
                                                        self.bc.b = (self.bc.b >> 1) | c;
                                                        self.af.f.z = self.bc.b == 0;
                                                    },
                                                    .c => {
                                                        self.af.f.c = (self.bc.c & 1) > 0;
                                                        self.bc.c = (self.bc.c >> 1) | c;
                                                        self.af.f.z = self.bc.c == 0;
                                                    },
                                                    .d => {
                                                        self.af.f.c = (self.de.d & 1) > 0;
                                                        self.de.d = (self.de.d >> 1) | c;
                                                        self.af.f.z = self.de.d == 0;
                                                    },
                                                    .e => {
                                                        self.af.f.c = (self.de.e & 1) > 0;
                                                        self.de.e = (self.de.e >> 1) | c;
                                                        self.af.f.z = self.de.e == 0;
                                                    },
                                                    .h => {
                                                        self.af.f.c = (self.hl.h & 1) > 0;
                                                        self.hl.h = (self.hl.h >> 1) | c;
                                                        self.af.f.z = self.hl.h == 0;
                                                    },
                                                    .l => {
                                                        self.af.f.c = (self.hl.l & 1) > 0;
                                                        self.hl.l = (self.hl.l >> 1) | c;
                                                        self.af.f.z = self.hl.l == 0;
                                                    },
                                                    .hl => {
                                                        var v = self.read(@bitCast(self.hl));
                                                        self.af.f.c = (v & 1) > 0;
                                                        v = (v >> 1) | c;
                                                        self.af.f.z = v == 0;
                                                        self.write(@bitCast(self.hl), v);
                                                    },
                                                }
                                                if (log) std.debug.print("RR {s}", .{@tagName(r.R)});
                                            },
                                            .sla => {
                                                const v = switch (r.R) {
                                                    .a => inner: {
                                                        const v = @shlWithOverflow(self.af.a, 1);
                                                        self.af.a = v.@"0";
                                                        break :inner v;
                                                    },
                                                    .b => inner: {
                                                        const v = @shlWithOverflow(self.bc.b, 1);
                                                        self.bc.b = v.@"0";
                                                        break :inner v;
                                                    },
                                                    .c => inner: {
                                                        const v = @shlWithOverflow(self.bc.c, 1);
                                                        self.bc.c = v.@"0";
                                                        break :inner v;
                                                    },
                                                    .d => inner: {
                                                        const v = @shlWithOverflow(self.de.d, 1);
                                                        self.de.d = v.@"0";
                                                        break :inner v;
                                                    },
                                                    .e => inner: {
                                                        const v = @shlWithOverflow(self.de.e, 1);
                                                        self.de.e = v.@"0";
                                                        break :inner v;
                                                    },
                                                    .h => inner: {
                                                        const v = @shlWithOverflow(self.hl.h, 1);
                                                        self.hl.h = v.@"0";
                                                        break :inner v;
                                                    },
                                                    .l => inner: {
                                                        const v = @shlWithOverflow(self.hl.l, 1);
                                                        self.hl.l = v.@"0";
                                                        break :inner v;
                                                    },
                                                    .hl => inner: {
                                                        const v = @shlWithOverflow(self.read(@bitCast(self.hl)), 1);
                                                        self.write(@bitCast(self.hl), v.@"0");
                                                        break :inner v;
                                                    },
                                                };
                                                self.af.f.z = v.@"0" == 0;
                                                self.af.f.c = v.@"1" == 1;
                                                if (log) std.debug.print("SLA {s}", .{@tagName(r.R)});
                                            },
                                            .sra => {
                                                switch (r.R) {
                                                    .a => {
                                                        const msb = self.af.a & 0x80;
                                                        self.af.f.c = (self.af.a & 1) > 0;
                                                        self.af.a = (self.af.a >> 1) | msb;
                                                        self.af.f.z = self.af.a == 0;
                                                    },
                                                    .b => {
                                                        const msb = self.bc.b & 0x80;
                                                        self.af.f.c = (self.bc.b & 1) > 0;
                                                        self.bc.b = (self.bc.b >> 1) | msb;
                                                        self.af.f.z = self.bc.b == 0;
                                                    },
                                                    .c => {
                                                        const msb = self.bc.c & 0x80;
                                                        self.af.f.c = (self.bc.c & 1) > 0;
                                                        self.bc.c = (self.bc.c >> 1) | msb;
                                                        self.af.f.z = self.bc.c == 0;
                                                    },
                                                    .d => {
                                                        const msb = self.de.d & 0x80;
                                                        self.af.f.c = (self.de.d & 1) > 0;
                                                        self.de.d = (self.de.d >> 1) | msb;
                                                        self.af.f.z = self.de.d == 0;
                                                    },
                                                    .e => {
                                                        const msb = self.de.e & 0x80;
                                                        self.af.f.c = (self.de.e & 1) > 0;
                                                        self.de.e = (self.de.e >> 1) | msb;
                                                        self.af.f.z = self.de.e == 0;
                                                    },
                                                    .h => {
                                                        const msb = self.hl.h & 0x80;
                                                        self.af.f.c = (self.hl.h & 1) > 0;
                                                        self.hl.h = (self.hl.h >> 1) | msb;
                                                        self.af.f.z = self.hl.h == 0;
                                                    },
                                                    .l => {
                                                        const msb = self.hl.l & 0x80;
                                                        self.af.f.c = (self.hl.l & 1) > 0;
                                                        self.hl.l = (self.hl.l >> 1) | msb;
                                                        self.af.f.z = self.hl.l == 0;
                                                    },
                                                    .hl => {
                                                        var v = self.read(@bitCast(self.hl));
                                                        const msb = v & 0x80;
                                                        self.af.f.c = (v & 1) > 0;
                                                        v = (v >> 1) | msb;
                                                        self.af.f.z = v == 0;
                                                        self.write(@bitCast(self.hl), v);
                                                    },
                                                }
                                                if (log) std.debug.print("SRA {s}", .{@tagName(r.R)});
                                            },
                                            .swap => {
                                                switch (r.R) {
                                                    .a => {
                                                        const t = self.af.a >> 4;
                                                        self.af.a = (self.af.a << 4) | t;
                                                        self.af.f.z = self.af.a == 0;
                                                    },
                                                    .b => {
                                                        const t = self.bc.b >> 4;
                                                        self.bc.b = (self.bc.b << 4) | t;
                                                        self.af.f.z = self.bc.b == 0;
                                                    },
                                                    .c => {
                                                        const t = self.bc.c >> 4;
                                                        self.bc.c = (self.bc.c << 4) | t;
                                                        self.af.f.z = self.bc.c == 0;
                                                    },
                                                    .d => {
                                                        const t = self.de.d >> 4;
                                                        self.de.d = (self.de.d << 4) | t;
                                                        self.af.f.z = self.de.d == 0;
                                                    },
                                                    .e => {
                                                        const t = self.de.e >> 4;
                                                        self.de.e = (self.de.e << 4) | t;
                                                        self.af.f.z = self.de.e == 0;
                                                    },
                                                    .h => {
                                                        const t = self.hl.h >> 4;
                                                        self.hl.h = (self.hl.h << 4) | t;
                                                        self.af.f.z = self.hl.h == 0;
                                                    },
                                                    .l => {
                                                        const t = self.hl.l >> 4;
                                                        self.hl.l = (self.hl.l << 4) | t;
                                                        self.af.f.z = self.hl.l == 0;
                                                    },
                                                    .hl => {
                                                        var v = self.read(@bitCast(self.hl));
                                                        const t = v >> 4;
                                                        v = (v << 4) | t;
                                                        self.af.f.z = v == 0;
                                                        self.write(@bitCast(self.hl), v);
                                                    },
                                                }
                                                self.af.f.c = false;
                                                if (log) std.debug.print("SWAP {s}", .{@tagName(r.R)});
                                            },
                                            .srl => {
                                                switch (r.R) {
                                                    .a => {
                                                        self.af.f.c = (self.af.a & 1) > 0;
                                                        self.af.a >>= 1;
                                                        self.af.f.z = self.af.a == 0;
                                                    },
                                                    .b => {
                                                        self.af.f.c = (self.bc.b & 1) > 0;
                                                        self.bc.b >>= 1;
                                                        self.af.f.z = self.bc.b == 0;
                                                    },
                                                    .c => {
                                                        self.af.f.c = (self.bc.c & 1) > 0;
                                                        self.bc.c >>= 1;
                                                        self.af.f.z = self.bc.c == 0;
                                                    },
                                                    .d => {
                                                        self.af.f.c = (self.de.d & 1) > 0;
                                                        self.de.d >>= 1;
                                                        self.af.f.z = self.de.d == 0;
                                                    },
                                                    .e => {
                                                        self.af.f.c = (self.de.e & 1) > 0;
                                                        self.de.e >>= 1;
                                                        self.af.f.z = self.de.e == 0;
                                                    },
                                                    .h => {
                                                        self.af.f.c = (self.hl.h & 1) > 0;
                                                        self.hl.h >>= 1;
                                                        self.af.f.z = self.hl.h == 0;
                                                    },
                                                    .l => {
                                                        self.af.f.c = (self.hl.l & 1) > 0;
                                                        self.hl.l >>= 1;
                                                        self.af.f.z = self.hl.l == 0;
                                                    },
                                                    .hl => {
                                                        var v = self.read(@bitCast(self.hl));
                                                        self.af.f.c = (v & 1) > 0;
                                                        v >>= 1;
                                                        self.af.f.z = v == 0;
                                                        self.write(@bitCast(self.hl), v);
                                                    },
                                                }
                                                if (log) std.debug.print("SRL {s}", .{@tagName(r.R)});
                                            },
                                        }
                                        self.af.f.n = false;
                                        self.af.f.h = false;
                                        break :blk if (hl) 4 else 2;
                                    },
                                    1 => {
                                        // BIT y, r[z]
                                        self.af.f.n = false;
                                        self.af.f.h = true;
                                        switch (r.R) {
                                            .a => self.af.f.z = (self.af.a & std.math.pow(u8, 2, cb.y.y)) == 0,
                                            .b => self.af.f.z = (self.bc.b & std.math.pow(u8, 2, cb.y.y)) == 0,
                                            .c => self.af.f.z = (self.bc.c & std.math.pow(u8, 2, cb.y.y)) == 0,
                                            .d => self.af.f.z = (self.de.d & std.math.pow(u8, 2, cb.y.y)) == 0,
                                            .e => self.af.f.z = (self.de.e & std.math.pow(u8, 2, cb.y.y)) == 0,
                                            .h => self.af.f.z = (self.hl.h & std.math.pow(u8, 2, cb.y.y)) == 0,
                                            .l => self.af.f.z = (self.hl.l & std.math.pow(u8, 2, cb.y.y)) == 0,
                                            .hl => {
                                                const v = self.read(@bitCast(self.hl));
                                                self.af.f.z = (v & std.math.pow(u8, 2, cb.y.y)) == 0;
                                                break :blk 3;
                                            },
                                        }
                                        if (log) std.debug.print("BIT {s}", .{@tagName(r.R)});
                                        break :blk 2;
                                    },
                                    2 => {
                                        // RES y, r[z]
                                        switch (r.R) {
                                            .a => self.af.a &= ~std.math.pow(u8, 2, cb.y.y),
                                            .b => self.bc.b &= ~std.math.pow(u8, 2, cb.y.y),
                                            .c => self.bc.c &= ~std.math.pow(u8, 2, cb.y.y),
                                            .d => self.de.d &= ~std.math.pow(u8, 2, cb.y.y),
                                            .e => self.de.e &= ~std.math.pow(u8, 2, cb.y.y),
                                            .h => self.hl.h &= ~std.math.pow(u8, 2, cb.y.y),
                                            .l => self.hl.l &= ~std.math.pow(u8, 2, cb.y.y),
                                            .hl => {
                                                var v = self.read(@bitCast(self.hl));
                                                v &= ~std.math.pow(u8, 2, cb.y.y);
                                                self.write(@bitCast(self.hl), v);
                                                break :blk 4;
                                            },
                                        }
                                        if (log) std.debug.print("RES {s}", .{@tagName(r.R)});
                                        break :blk 2;
                                    },
                                    3 => {
                                        // 	SET y, r[z]
                                        switch (r.R) {
                                            .a => self.af.a |= std.math.pow(u8, 2, cb.y.y),
                                            .b => self.bc.b |= std.math.pow(u8, 2, cb.y.y),
                                            .c => self.bc.c |= std.math.pow(u8, 2, cb.y.y),
                                            .d => self.de.d |= std.math.pow(u8, 2, cb.y.y),
                                            .e => self.de.e |= std.math.pow(u8, 2, cb.y.y),
                                            .h => self.hl.h |= std.math.pow(u8, 2, cb.y.y),
                                            .l => self.hl.l |= std.math.pow(u8, 2, cb.y.y),
                                            .hl => {
                                                var v = self.read(@bitCast(self.hl));
                                                v |= std.math.pow(u8, 2, cb.y.y);
                                                self.write(@bitCast(self.hl), v);
                                                break :blk 4;
                                            },
                                        }
                                        if (log) std.debug.print("SET {s}", .{@tagName(r.R)});
                                        break :blk 2;
                                    },
                                }
                            },
                            2...5 => {
                                // invalid
                                self.mode = .hang;
                                break :blk 0;
                            },
                            6 => {
                                // DI
                                self.ime = false;
                                if (log) std.debug.print("DI", .{});
                                break :blk 1;
                            },
                            7 => {
                                // EI
                                self.ei_pending = true;
                                if (log) std.debug.print("EI", .{});
                                break :blk 1;
                            },
                        }
                    },
                    4 => {
                        switch (opcode.y.y) {
                            0...3 => {
                                // CALL cc[y], nn
                                var nn: u16 = self.fetch();
                                nn |= @as(u16, self.fetch()) << 8;
                                const cc: Operand = .{ .CC = @enumFromInt(opcode.y.y) };
                                const take = switch (cc.CC) {
                                    .nz => !self.af.f.z,
                                    .z => self.af.f.z,
                                    .nc => !self.af.f.c,
                                    .c => self.af.f.c,
                                };
                                if (take) self.call(nn);
                                if (log) std.debug.print("CALL {s}, {X:0>4}", .{ @tagName(cc.CC), nn });
                                break :blk if (take) 6 else 3;
                            },
                            4...7 => {
                                // invalid
                                self.mode = .hang;
                                break :blk 0;
                            },
                        }
                    },
                    5 => {
                        switch (opcode.y.pq.q) {
                            0 => {
                                // PUSH rp2[p]
                                const rp2: Operand = .{ .RP2 = @enumFromInt(opcode.y.pq.p) };
                                switch (rp2.RP2) {
                                    .bc => {
                                        self.sp -%= 1;
                                        self.write(self.sp, self.bc.b);
                                        self.sp -%= 1;
                                        self.write(self.sp, self.bc.c);
                                    },
                                    .de => {
                                        self.sp -%= 1;
                                        self.write(self.sp, self.de.d);
                                        self.sp -%= 1;
                                        self.write(self.sp, self.de.e);
                                    },
                                    .hl => {
                                        self.sp -%= 1;
                                        self.write(self.sp, self.hl.h);
                                        self.sp -%= 1;
                                        self.write(self.sp, self.hl.l);
                                    },
                                    .af => {
                                        self.sp -%= 1;
                                        self.write(self.sp, self.af.a);
                                        self.sp -%= 1;
                                        self.write(self.sp, @bitCast(self.af.f));
                                    },
                                }
                                if (log) std.debug.print("PUSH {s}", .{@tagName(rp2.RP2)});
                                break :blk 4;
                            },
                            1 => {
                                switch (opcode.y.pq.p) {
                                    0 => {
                                        // CALL nn
                                        var nn: u16 = self.fetch();
                                        nn |= @as(u16, self.fetch()) << 8;
                                        self.call(nn);
                                        if (log) std.debug.print("CALL {X:0>4}", .{nn});
                                        break :blk 6;
                                    },
                                    1...3 => {
                                        // invalid
                                        self.mode = .hang;
                                        break :blk 0;
                                    },
                                }
                            },
                        }
                    },
                    6 => {
                        // alu[y] n
                        const b: u8 = self.fetch();
                        const alu: Operand = .{ .ALU = @enumFromInt(opcode.y.y) };
                        switch (alu.ALU) {
                            .add => {
                                const a = self.af.a;
                                const v = @addWithOverflow(a, b);
                                self.af.a = v.@"0";
                                self.af.f.n = false;
                                self.af.f.z = v.@"0" == 0;
                                self.af.f.c = v.@"1" == 1;
                                self.af.f.h = (a ^ b ^ v.@"0") & 0x10 != 0;
                                if (log) std.debug.print("ADD {X:0>2}", .{b});
                            },
                            .adc => {
                                const a = self.af.a;
                                const c = @as(u8, if (self.af.f.c) 1 else 0);
                                const vp = @addWithOverflow(a, b);
                                const v = @addWithOverflow(vp.@"0", c);
                                self.af.a = v.@"0";
                                self.af.f.n = false;
                                self.af.f.z = v.@"0" == 0;
                                self.af.f.c = v.@"1" == 1 or vp.@"1" == 1;
                                self.af.f.h = (a ^ b ^ c ^ v.@"0") & 0x10 != 0;
                                if (log) std.debug.print("ADC {X:0>2}", .{b});
                            },
                            .sub => {
                                const a = self.af.a;
                                const v = @subWithOverflow(a, b);
                                self.af.a = v.@"0";
                                self.af.f.n = true;
                                self.af.f.z = v.@"0" == 0;
                                self.af.f.c = v.@"1" == 1;
                                self.af.f.h = (a ^ b ^ v.@"0") & 0x10 != 0;
                                if (log) std.debug.print("SUB {X:0>2}", .{b});
                            },
                            .sbc => {
                                const a = self.af.a;
                                const c = @as(u8, if (self.af.f.c) 1 else 0);
                                const vp = @subWithOverflow(a, b);
                                const v = @subWithOverflow(vp.@"0", c);
                                self.af.a = v.@"0";
                                self.af.f.n = true;
                                self.af.f.z = v.@"0" == 0;
                                self.af.f.c = v.@"1" == 1 or vp.@"1" == 1;
                                self.af.f.h = (a ^ b ^ c ^ v.@"0") & 0x10 != 0;
                                if (log) std.debug.print("SBC {X:0>2}", .{b});
                            },
                            .@"and" => {
                                self.af.a &= b;
                                self.af.f.z = self.af.a == 0;
                                self.af.f.h = true;
                                self.af.f.n = false;
                                self.af.f.c = false;
                                if (log) std.debug.print("AND {X:0>2}", .{b});
                            },
                            .xor => {
                                self.af.a ^= b;
                                self.af.f.z = self.af.a == 0;
                                self.af.f.h = false;
                                self.af.f.n = false;
                                self.af.f.c = false;
                                if (log) std.debug.print("XOR {X:0>2}", .{b});
                            },
                            .@"or" => {
                                self.af.a |= b;
                                self.af.f.z = self.af.a == 0;
                                self.af.f.h = false;
                                self.af.f.n = false;
                                self.af.f.c = false;
                                if (log) std.debug.print("OR {X:0>2}", .{b});
                            },
                            .cp => {
                                const a = self.af.a;
                                const v = @subWithOverflow(a, b);
                                self.af.f.n = true;
                                self.af.f.z = v.@"0" == 0;
                                self.af.f.c = v.@"1" == 1;
                                self.af.f.h = (a ^ b ^ v.@"0") & 0x10 != 0;
                                if (log) std.debug.print("CP {X:0>2}", .{b});
                            },
                        }
                        break :blk 2;
                    },
                    7 => {
                        // RST y*8
                        self.call(@as(u16, opcode.y.y) * 8);
                        if (log) std.debug.print("RST {X:0>2}", .{@as(u16, opcode.y.y)});
                        break :blk 4;
                    },
                }
            },
        };

        if (log) std.debug.print("\tPC:{X:0>4}\tSP:{X:0>4}\tAF:{X:0>4}\tBC:{X:0>4}\tDE:{X:0>4}\tHL:{X:0>4}\tIME:{d}\n", .{
            self.pc,
            self.sp,
            @as(u16, @bitCast(self.af)),
            @as(u16, @bitCast(self.bc)),
            @as(u16, @bitCast(self.de)),
            @as(u16, @bitCast(self.hl)),
            @as(u8, if (self.ime) 1 else 0),
        });
    }

    pub fn reset(self: *CPU) void {
        self.cycle_counter = 0;
        self.mode = .normal;
        self.ime = false;
        self.ei_pending = false;

        self.pc = 0x100;
        self.sp = 0xfffe;
        self.af = @bitCast(@as(u16, 0x1180));
        self.bc = @bitCast(@as(u16, 0));
        self.de = @bitCast(@as(u16, 0xff56));
        self.hl = @bitCast(@as(u16, 0x000d));
    }

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("cycle_counter");
        try jw.write(self.cycle_counter);
        try jw.objectField("mode");
        try jw.write(self.mode);
        try jw.objectField("pc");
        try jw.write(self.pc);
        try jw.objectField("sp");
        try jw.write(self.sp);
        try jw.objectField("ime");
        try jw.write(self.ime);
        try jw.objectField("ei_pending");
        try jw.write(self.ei_pending);

        try jw.objectField("af");
        try jw.beginObject();
        try jw.objectField("a");
        try jw.write(self.af.a);
        try jw.objectField("f");
        try jw.beginObject();
        try jw.objectField("c");
        try jw.write(self.af.f.c);
        try jw.objectField("h");
        try jw.write(self.af.f.h);
        try jw.objectField("n");
        try jw.write(self.af.f.n);
        try jw.objectField("z");
        try jw.write(self.af.f.z);
        try jw.endObject();
        try jw.endObject();

        try jw.objectField("bc");
        try jw.beginObject();
        try jw.objectField("b");
        try jw.write(self.bc.b);
        try jw.objectField("c");
        try jw.write(self.bc.c);
        try jw.endObject();

        try jw.objectField("de");
        try jw.beginObject();
        try jw.objectField("d");
        try jw.write(self.de.d);
        try jw.objectField("e");
        try jw.write(self.de.e);
        try jw.endObject();

        try jw.objectField("hl");
        try jw.beginObject();
        try jw.objectField("h");
        try jw.write(self.hl.h);
        try jw.objectField("l");
        try jw.write(self.hl.l);
        try jw.endObject();

        try jw.endObject();
    }
};
