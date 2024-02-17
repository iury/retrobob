const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// STore X register
//
// M = X
//
// MODE          SYNTAX        HEX LEN TIM
// Zero Page     STX $44       $86  2   3
// Zero Page,Y   STX $44,Y     $96  2   4
// Absolute      STX $4400     $8E  3   4

pub fn stx(self: *CPU, addressing: Addressing) void {
    switch (addressing) {
        .zpg, .zpx, .zpy => |v| {
            self.write(v, self.x);
        },
        .abs => |v| {
            self.write(v, self.x);
        },
        else => {},
    }
}
