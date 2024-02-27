const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Transfer Accumulator to Y
//
// Y = A
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       TAY           $A8  1   2

pub fn tay(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.y = self.acc;
    self.z = self.y == 0;
    self.n = (self.y & 0x80) > 0;
}
