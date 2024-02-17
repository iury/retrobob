const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Clear Carry
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       CLC           $18  1   2

pub fn clc(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.c = false;
}
