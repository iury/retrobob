const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Bitwise Exclusive OR (XOR)
//
// A,Z,N = A^M
//
// Affects Flags: N Z
//
// MODE          SYNTAX        HEX LEN TIM
// Immediate     EOR #$44      $49  2   2
// Zero Page     EOR $44       $45  2   3
// Zero Page,X   EOR $44,X     $55  2   4
// Absolute      EOR $4400     $4D  3   4
// Absolute,X    EOR $4400,X   $5D  3   4+
// Absolute,Y    EOR $4400,Y   $59  3   4+
// Indirect,X    EOR ($44,X)   $41  2   6
// Indirect,Y    EOR ($44),Y   $51  2   5+
//
// + add 1 cycle if page boundary crossed

pub fn eor(self: *CPU, addressing: Addressing) void {
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

    self.acc = a ^ b;
    self.z = self.acc == 0;
    self.n = (self.acc & 0x80) > 0;
}
