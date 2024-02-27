const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Transfer Accumulator to X
//
// X = A
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       TAX           $AA  1   2

pub fn tax(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.x = self.acc;
    self.z = self.x == 0;
    self.n = (self.x & 0x80) > 0;
}
