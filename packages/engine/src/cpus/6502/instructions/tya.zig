const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Transfer Y to A
//
// A = Y
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       TYA           $98  1   2

pub fn tya(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.acc = self.y;
    self.z = self.acc == 0;
    self.n = (self.acc & 0x80) > 0;
}
