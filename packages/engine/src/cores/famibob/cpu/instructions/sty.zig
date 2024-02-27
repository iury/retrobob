const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// STore Y register
//
// M = Y
//
// MODE          SYNTAX        HEX LEN TIM
// Zero Page     STY $44       $84  2   3
// Zero Page,X   STY $44,Y     $94  2   4
// Absolute      STY $4400     $8C  3   4

pub fn sty(self: *CPU, addressing: Addressing) void {
    switch (addressing) {
        .zpg, .zpx, .zpy => |v| {
            self.write(v, self.y);
        },
        .abs => |v| {
            self.write(v, self.y);
        },
        else => {},
    }
}
