const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Transfer X to A
//
// A = X
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       TXA           $8A  1   2

pub fn txa(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.acc = self.x;
    self.z = self.acc == 0;
    self.n = (self.acc & 0x80) > 0;
}
