const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// DEcrement X
//
// X,Z,N = X-1
//
// Affects Flags: N Z
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       DEX           $CA  1   2

pub fn dex(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.x -%= 1;
    self.z = self.x == 0;
    self.n = (self.x & 0x80) > 0;
}
