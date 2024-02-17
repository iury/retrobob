const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// ReTurn from Interrupt
//
// pull P, pull PC, JMP
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       RTI           $40  1   6

pub fn rti(self: *CPU, addressing: Addressing) void {
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
        self.setP(self.read(0x100 | @as(u16, self.sp)));
        self.sp +%= 1;
        self.b = false;
        self.next_cycle = .read;
        return;
    } else if (self.cycle_counter == 5) {
        self.pc = self.read(0x100 | @as(u16, self.sp));
        self.sp +%= 1;
        self.next_cycle = .read;
        return;
    } else {
        self.pc |= @as(u16, self.read(0x100 | @as(u16, self.sp))) << 8;
    }
}

test {
    _ = @import("rti.test.zig");
}
