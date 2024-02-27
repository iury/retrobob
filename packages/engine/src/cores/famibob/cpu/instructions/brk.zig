const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// * BReaK
// *
// * Affects Flags: B
// *
// * push PC, push P, JMP (0xFFFF/E)
// *
// * Affects Flags: B
// *
// * MODE          SYNTAX        HEX LEN TIM
// * Implied       BRK           $00  1   7

pub fn brk(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    if (self.cycle_counter == 2) {
        self.b = true;
        _ = self.fetch();
        self.next_cycle = .write;
        return;
    } else if (self.cycle_counter == 3) {
        self.write(0x100 | @as(u16, self.sp), @truncate(self.pc >> 8));
        self.sp -%= 1;
        self.next_cycle = .write;
        return;
    } else if (self.cycle_counter == 4) {
        self.write(0x100 | @as(u16, self.sp), @as(u8, @truncate(self.pc & 0xff)));
        self.sp -%= 1;
        self.next_cycle = .write;
        return;
    } else if (self.cycle_counter == 5) {
        self.write(0x100 | @as(u16, self.sp), self.getP() | 0x10);
        self.sp -%= 1;
        self.next_cycle = .read;
        return;
    } else if (self.cycle_counter == 6) {
        self.pc &= @as(u16, 0xff00);
        self.pc |= self.read(if (self.nmi_requested) 0xfffa else 0xfffe);
        self.i = true;
        self.next_cycle = .read;
        return;
    } else {
        self.pc &= 0xff;
        self.pc <<= 8;
        self.pc |= self.read(if (self.nmi_requested) 0xfffb else 0xffff);
    }
}

test {
    _ = @import("brk.test.zig");
}
