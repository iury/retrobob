const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Set Interrupt Disabled
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       SEI           $78  1   2

pub fn sei(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.i = true;
}
