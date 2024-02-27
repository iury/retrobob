const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// ComPare X register
//
// Z,C,N = X-M
//
// Affects Flags: N Z C
//
// MODE          SYNTAX        HEX LEN TIM
// Immediate     CPX #$44      $E0  2   2
// Zero Page     CPX $44       $E4  2   3
// Absolute      CPX $4400     $EC  3   4

pub fn cpx(self: *CPU, addressing: Addressing) void {
    const a = self.x;
    var b: u8 = 0;

    switch (addressing) {
        .imm => |v| {
            b = v;
        },
        .zpg => |v| {
            b = self.read(v);
        },
        .abs => |v| {
            b = self.read(v);
        },
        else => {},
    }

    self.c = a >= b;
    self.z = a == b;
    const v = a -% b;
    self.n = (v & 0x80) > 0;
}
