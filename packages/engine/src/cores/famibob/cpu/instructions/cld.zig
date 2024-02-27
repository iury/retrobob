const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Clear Decimal Mode
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       CLD           $D8  1   2

pub fn cld(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.d = false;
}
