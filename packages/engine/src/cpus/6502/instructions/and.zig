const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Bitwise AND with accumulator
//
// A,Z,N = A&M
//
// Affects Flags: N Z
//
// MODE          SYNTAX        HEX LEN TIM
// Immediate     AND #$44      $29  2   2
// Zero Page     AND $44       $25  2   3
// Zero Page,X   AND $44,X     $35  2   4
// Absolute      AND $4400     $2D  3   4
// Absolute,X    AND $4400,X   $3D  3   4+
// Absolute,Y    AND $4400,Y   $39  3   4+
// Indirect,X    AND ($44,X)   $21  2   6
// Indirect,Y    AND ($44),Y   $31  2   5+
//
// + add 1 cycle if page boundary crossed

pub fn @"and"(self: *CPU, addressing: Addressing) void {
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

    self.acc = a & b;
    self.z = self.acc == 0;
    self.n = (self.acc & 0x80) > 0;
}
