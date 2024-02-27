const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// PusH Processor flags (in the stack)
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       PHP           $08  1   3

pub fn php(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    if (self.cycle_counter == 2) {
        _ = self.fetch();
        self.pc -%= 1;
        self.next_cycle = .write;
        return;
    } else {
        self.write(0x100 | @as(u16, self.sp), self.getP() | 0x10);
        self.sp -%= 1;
    }
}
