const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Transfer Stack pointer to X
//
// X = SP
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       TSX           $BA  1   2

pub fn tsx(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.x = self.sp;
    self.z = self.x == 0;
    self.n = (self.x & 0x80) > 0;
}
