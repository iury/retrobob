const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// PulL Processor flags (from the stack)
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       PLP           $28  1   4

pub fn plp(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    if (self.cycle_counter == 2) {
        _ = self.fetch();
        self.pc -%= 1;
        self.next_cycle = .read;
        return;
    } else if (self.cycle_counter == 3) {
        self.sp +%= 1;
        self.next_cycle = .read;
        return;
    } else {
        self.setP(self.read(0x100 | @as(u16, self.sp)));
        self.b = false;
    }
}

test {
    _ = @import("plp.test.zig");
}
