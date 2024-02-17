const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Clear Interrupt Disabled
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       CLI           $58  1   2

pub fn cli(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.i = false;
}
