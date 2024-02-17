const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Clear oVerflow
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       CLV           $B8  1   2

pub fn clv(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.v = false;
}
