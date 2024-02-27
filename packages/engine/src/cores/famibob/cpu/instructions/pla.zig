const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// * PulL Accumulator (from the stack)
// *
// * MODE          SYNTAX        HEX LEN TIM
// * Implied       PLA           $68  1   4
// *
// * Affects Flags: N Z

pub fn pla(self: *CPU, addressing: Addressing) void {
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
        self.acc = self.read(0x100 | @as(u16, self.sp));
        self.z = self.acc == 0;
        self.n = (self.acc & 0x80) > 0;
    }
}

test {
    _ = @import("pla.test.zig");
}
