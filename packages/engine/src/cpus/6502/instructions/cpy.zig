const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// ComPare Y register
//
// Z,C,N = Y-M
//
// Affects Flags: N Z C
//
// MODE          SYNTAX        HEX LEN TIM
// Immediate     CPY #$44      $C0  2   2
// Zero Page     CPY $44       $C4  2   3
// Absolute      CPY $4400     $CC  3   4

pub fn cpy(self: *CPU, addressing: Addressing) void {
    const a = self.y;
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
