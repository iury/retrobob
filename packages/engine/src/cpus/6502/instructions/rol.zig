const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// ROtate Left
//
// Affects Flags: N Z C
//
// MODE          SYNTAX        HEX LEN TIM
// Accumulator   ROL A         $2A  1   2
// Zero Page     ROL $44       $26  2   5
// Zero Page,X   ROL $44,X     $36  2   6
// Absolute      ROL $4400     $2E  3   6
// Absolute,X    ROL $4400,X   $3E  3   7

pub fn rol(self: *CPU, addressing: Addressing) void {
    const S = struct {
        var address: u16 = 0;
        var value: u8 = 0;
    };

    switch (addressing) {
        .acc => |_| {
            const c = if (self.c) @as(u8, 1) else 0;
            self.c = (self.acc & 0x80) > 0;
            self.acc = (self.acc << 1) | c;
            self.z = self.acc == 0;
            self.n = (self.acc & 0x80) > 0;
            return;
        },
        .zpg => |v| {
            S.address = v;
            if (self.cycle_counter == 3) {
                S.value = self.read(v);
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 4) {
                self.write(v, S.value);
                self.next_cycle = .write;
                return;
            }
        },
        .zpx, .zpy => |v| {
            S.address = v;
            if (self.cycle_counter == 4) {
                S.value = self.read(v);
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 5) {
                self.write(v, S.value);
                self.next_cycle = .write;
                return;
            }
        },
        .abs => |v| {
            S.address = v;
            if (self.cycle_counter == 4) {
                S.value = self.read(v);
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 5) {
                self.write(v, S.value);
                self.next_cycle = .write;
                return;
            }
        },
        .abx, .aby => |v| {
            S.address = v.@"0";
            if (self.cycle_counter == 4) {
                _ = self.read(v.@"0");
                self.next_cycle = .read;
                return;
            } else if (self.cycle_counter == 5) {
                S.value = self.read(v.@"0");
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 6) {
                self.write(v.@"0", S.value);
                self.next_cycle = .write;
                return;
            }
        },
        else => {},
    }

    const c = if (self.c) @as(u8, 1) else 0;
    self.c = (S.value & 0x80) > 0;
    S.value = (S.value << 1) | c;
    self.write(S.address, S.value);
    self.z = S.value == 0;
    self.n = (S.value & 0x80) > 0;
}

test {
    _ = @import("rol.test.zig");
}
