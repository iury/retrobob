const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// PusH Accumulator (in the stack)
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       PHA           $48  1   3

pub fn pha(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    if (self.cycle_counter == 2) {
        _ = self.fetch();
        self.pc -%= 1;
        self.next_cycle = .write;
        return;
    } else {
        self.write(0x100 | @as(u16, self.sp), self.acc);
        self.sp -%= 1;
    }
}
