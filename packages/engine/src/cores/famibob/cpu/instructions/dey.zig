const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// DEcrement Y
//
// Y,Z,N = Y-1
//
// Affects Flags: N Z
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       DEY           $88  1   2

pub fn dey(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.y -%= 1;
    self.z = self.y == 0;
    self.n = (self.y & 0x80) > 0;
}
