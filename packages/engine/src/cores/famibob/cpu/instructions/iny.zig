const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// INcrement Y
//
// Y,Z,N = Y+1
//
// Affects Flags: N Z
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       INY           $C8  1   2

pub fn iny(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.y +%= 1;
    self.z = self.y == 0;
    self.n = (self.y & 0x80) > 0;
}
