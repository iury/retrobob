const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Set Carry
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       SEC           $38  1   2

pub fn sec(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.c = true;
}
