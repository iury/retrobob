const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Jump to SubRoutine
//
// push PC-1, JMP
//
// MODE          SYNTAX        HEX LEN TIM
// Absolute      JSR $5597     $20  3   6

pub fn jsr(self: *CPU, addressing: Addressing) void {
    if (self.cycle_counter == 4) {
        self.pc -%= 1;
        self.write(0x100 | @as(u16, self.sp), @truncate(self.pc >> 8));
        self.sp -%= 1;
        self.next_cycle = .write;
        return;
    } else if (self.cycle_counter == 5) {
        self.write(0x100 | @as(u16, self.sp), @truncate(self.pc & 0xff));
        self.sp -%= 1;
        self.next_cycle = .read;
        return;
    } else {
        switch (addressing) {
            .abs => |v| {
                self.pc = v;
            },
            else => {},
        }
    }
}
