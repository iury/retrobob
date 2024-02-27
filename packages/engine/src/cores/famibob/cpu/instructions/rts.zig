const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// ReTurn from Subroutine
//
// pull PC, PC++, JMP
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       RTS           $60  1   6

pub fn rts(self: *CPU, addressing: Addressing) void {
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
    } else if (self.cycle_counter == 4) {
        self.pc = self.read(0x100 | @as(u16, self.sp));
        self.sp +%= 1;
        self.next_cycle = .read;
        return;
    } else if (self.cycle_counter == 5) {
        self.pc |= @as(u16, self.read(0x100 | @as(u16, self.sp))) << 8;
        self.next_cycle = .read;
        return;
    } else {
        self.pc +%= 1;
    }
}

test {
    _ = @import("rts.test.zig");
}
