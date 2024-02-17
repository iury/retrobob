const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// BIT test
//
// A & M, N = M7, V = M6
//
// Affects Flags: N V Z
//
// MODE          SYNTAX        HEX LEN TIM
// Zero Page     BIT $44       $24  2   3
// Absolute      BIT $4400     $2C  3   4

pub fn bit(self: *CPU, addressing: Addressing) void {
    const a = self.acc;
    var b: u8 = 0;

    switch (addressing) {
        .zpg => |v| {
            b = self.read(v);
        },
        .abs => |v| {
            b = self.read(v);
        },
        else => {},
    }

    self.z = (a & b) == 0;
    self.v = (b & 0x40) > 0;
    self.n = (b & 0x80) > 0;
}
