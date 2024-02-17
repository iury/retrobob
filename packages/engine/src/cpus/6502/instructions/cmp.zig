const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// CoMPare accumulator
//
// Z,C,N = A-M
//
// Affects Flags: N Z C
//
// MODE          SYNTAX        HEX LEN TIM
// Immediate     CMP #$44      $C9  2   2
// Zero Page     CMP $44       $C5  2   3
// Zero Page,X   CMP $44,X     $D5  2   4
// Absolute      CMP $4400     $CD  3   4
// Absolute,X    CMP $4400,X   $DD  3   4+
// Absolute,Y    CMP $4400,Y   $D9  3   4+
// Indirect,X    CMP ($44,X)   $C1  2   6
// Indirect,Y    CMP ($44),Y   $D1  2   5+
//
// + add 1 cycle if page boundary crossed

pub fn cmp(self: *CPU, addressing: Addressing) void {
    const a = self.acc;
    var b: u8 = 0;

    switch (addressing) {
        .imm => |v| {
            b = v;
        },
        .zpg, .zpx, .zpy => |v| {
            b = self.read(v);
        },
        .abs => |v| {
            b = self.read(v);
        },
        .abx, .aby => |v| {
            b = self.read(v.@"0");
        },
        .idx => |v| {
            b = self.read(v.@"0");
        },
        .idy => |v| {
            b = self.read(v.@"0");
        },
        else => {},
    }

    self.c = a >= b;
    self.z = a == b;
    const v = a -% b;
    self.n = (v & 0x80) > 0;
}
