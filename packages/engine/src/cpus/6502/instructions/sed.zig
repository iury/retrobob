const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Set Decimal Mode
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       SED           $F8  1   2

pub fn sed(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.d = true;
}
