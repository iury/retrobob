const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// LoaD Y
//
// Y,Z,N = M
//
// Affects Flags: N Z
//
// MODE          SYNTAX        HEX LEN TIM
// Immediate     LDY #$44      $A0  2   2
// Zero Page     LDY $44       $A4  2   3
// Zero Page,X   LDY $44,X     $B4  2   4
// Absolute      LDY $4400     $AC  3   4
// Absolute,X    LDY $4400,X   $BC  3   4+
//
// + add 1 cycle if page boundary crossed

pub fn ldy(self: *CPU, addressing: Addressing) void {
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
        else => {},
    }

    self.y = b;
    self.z = self.y == 0;
    self.n = (self.y & 0x80) > 0;
}
