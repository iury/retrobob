const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Bitwise OR with Accumulator
//
// A,Z,N = A|M
//
// Affects Flags: N Z
//
// MODE          SYNTAX        HEX LEN TIM
// Immediate     ORA #$44      $09  2   2
// Zero Page     ORA $44       $05  2   3
// Zero Page,X   ORA $44,X     $15  2   4
// Absolute      ORA $4400     $0D  3   4
// Absolute,X    ORA $4400,X   $1D  3   4+
// Absolute,Y    ORA $4400,Y   $19  3   4+
// Indirect,X    ORA ($44,X)   $01  2   6
// Indirect,Y    ORA ($44),Y   $11  2   5+
//
// + add 1 cycle if page boundary crossed

pub fn ora(self: *CPU, addressing: Addressing) void {
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

    self.acc = a | b;
    self.z = self.acc == 0;
    self.n = (self.acc & 0x80) > 0;
}
