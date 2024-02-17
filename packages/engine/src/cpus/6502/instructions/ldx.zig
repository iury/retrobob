const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// LoaD X
//
// X,Z,N = M
//
// Affects Flags: N Z
//
// MODE          SYNTAX        HEX LEN TIM
// Immediate     LDX #$44      $A2  2   2
// Zero Page     LDX $44       $A6  2   3
// Zero Page,Y   LDX $44,Y     $B6  2   4
// Absolute      LDX $4400     $AE  3   4
// Absolute,Y    LDX $4400,Y   $BE  3   4+
//
// + add 1 cycle if page boundary crossed

pub fn ldx(self: *CPU, addressing: Addressing) void {
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

    self.x = b;
    self.z = self.x == 0;
    self.n = (self.x & 0x80) > 0;
}
