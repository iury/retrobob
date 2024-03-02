const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Hardware Interrupt
//
// Affects Flags: B
//
// MODE          SYNTAX        HEX LEN TIM
// Implied       ---           ---  -   7

pub fn irq(self: *CPU) void {
    self.irq_cycle += 1;

    if (self.irq_cycle == 1) {
        if (self.rst_requested) {
            self.irq_type = .rst;
        } else if (self.nmi_requested) {
            self.irq_type = .nmi;
        } else {
            self.irq_type = .irq;
        }

        self.b = false;
        self.opcode = 0;
        _ = self.fetch();
        self.pc -%= 1;
        return;
    } else if (self.irq_cycle == 2) {
        _ = self.fetch();
        self.pc -%= 1;
        return;
    } else if (self.irq_cycle == 3) {
        if (!self.rst_requested) self.write(0x100 | @as(u16, self.sp), @truncate(self.pc >> 8));
        self.sp -%= 1;
        return;
    } else if (self.irq_cycle == 4) {
        if (!self.rst_requested) self.write(0x100 | @as(u16, self.sp), @truncate(self.pc & 0xff));
        self.sp -%= 1;
        return;
    } else if (self.irq_cycle == 5) {
        if (!self.rst_requested) self.write(0x100 | @as(u16, self.sp), self.getP() & ~@as(u8, 0x10));
        self.sp -%= 1;
        return;
    } else if (self.irq_cycle == 6) {
        var pch: u16 = 0;
        if (self.irq_type == .rst) {
            pch = 0xfffd;
        } else if (self.irq_type == .nmi) {
            pch = 0xfffb;
        } else {
            pch = 0xffff;
        }
        self.pc &= 0xff00;
        self.pc |= self.read(pch);
        return;
    } else {
        self.irq_cycle = 0;
        var pcl: u16 = 0;
        self.irq_occurred = false;
        if (self.irq_type == .rst) {
            self.rst_requested = false;
            pcl = 0xfffc;
        } else if (self.irq_type == .nmi) {
            self.nmi_requested = false;
            pcl = 0xfffa;
        } else {
            self.irq_requested = false;
            pcl = 0xfffe;
        }
        self.pc &= 0xff;
        self.pc <<= 8;
        self.pc |= self.read(pcl);
        self.i = true;
    }
}

test {
    _ = @import("irq.test.zig");
}
