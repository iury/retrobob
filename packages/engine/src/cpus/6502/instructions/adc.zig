const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// ADd with Carry
//
// A,Z,C,N = A+M+C
//
// Affects Flags: N V Z C
//
// MODE          SYNTAX        HEX LEN TIM
// Immediate     ADC #$44      $69  2   2
// Zero Page     ADC $44       $65  2   3
// Zero Page,X   ADC $44,X     $75  2   4
// Absolute      ADC $4400     $6D  3   4
// Absolute,X    ADC $4400,X   $7D  3   4+
// Absolute,Y    ADC $4400,Y   $79  3   4+
// Indirect,X    ADC ($44,X)   $61  2   6
// Indirect,Y    ADC ($44),Y   $71  2   5+
//
// + add 1 cycle if page boundary crossed

pub fn adc(self: *CPU, addressing: Addressing) void {
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

    const sum1 = @addWithOverflow(a, b);
    const sum2 = @addWithOverflow(sum1.@"0", if (self.c) @as(u8, 1) else 0);
    const result = sum2.@"0";

    self.acc = result;
    self.z = result == 0;
    self.n = (result & 0x80) > 0;
    self.v = ((a ^ result) & (b ^ result) & 0x80) > 0;
    self.c = sum1.@"1" == 1 or sum2.@"1" == 1;
}

test {
    _ = @import("adc.test.zig");
}
