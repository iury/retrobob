const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// LoaD Accumulator
//
// A,Z,N = M
//
// Affects Flags: N Z
//
// MODE          SYNTAX        HEX LEN TIM
// Immediate     LDA #$44      $A9  2   2
// Zero Page     LDA $44       $A5  2   3
// Zero Page,X   LDA $44,X     $B5  2   4
// Absolute      LDA $4400     $AD  3   4
// Absolute,X    LDA $4400,X   $BD  3   4+
// Absolute,Y    LDA $4400,Y   $B9  3   4+
// Indirect,X    LDA ($44,X)   $A1  2   6
// Indirect,Y    LDA ($44),Y   $B1  2   5+
//
// + add 1 cycle if page boundary crossed

pub fn lda(self: *CPU, addressing: Addressing) void {
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

    self.acc = b;
    self.z = self.acc == 0;
    self.n = (self.acc & 0x80) > 0;
}
