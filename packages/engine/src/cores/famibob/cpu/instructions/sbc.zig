const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// SuBtract with Carry
//
// A,Z,C,N = A-M-(1-C)
//
// Affects Flags: N V Z C
//
// MODE          SYNTAX        HEX LEN TIM
// Immediate     SBC #$44      $E9  2   2
// Zero Page     SBC $44       $E5  2   3
// Zero Page,X   SBC $44,X     $F5  2   4
// Absolute      SBC $4400     $ED  3   4
// Absolute,X    SBC $4400,X   $FD  3   4+
// Absolute,Y    SBC $4400,Y   $F9  3   4+
// Indirect,X    SBC ($44,X)   $E1  2   6
// Indirect,Y    SBC ($44),Y   $F1  2   5+
//
// + add 1 cycle if page boundary crossed

pub fn sbc(self: *CPU, addressing: Addressing) void {
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

    const sub1 = @subWithOverflow(a, b);
    const sub2 = @subWithOverflow(sub1.@"0", if (self.c) 0 else @as(u8, 1));
    const result = sub2.@"0";

    self.acc = result;
    self.z = result == 0;
    self.n = (result & 0x80) > 0;
    self.v = ((a ^ result) & ((255 - b) ^ result) & 0x80) > 0;
    self.c = sub1.@"1" == 0 and sub2.@"1" == 0;
}

test {
    _ = @import("sbc.test.zig");
}
