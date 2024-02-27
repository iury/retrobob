const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Transfer X to Stack pointer
//
// SP = X
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       TXS           $9A  1   2

pub fn txs(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.sp = self.x;
}
