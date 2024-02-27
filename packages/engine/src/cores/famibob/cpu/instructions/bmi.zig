const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Branch if Minus
//
// MODE          SYNTAX        HEX LEN TIM
// Relative      BMI LABEL     $30  2   2+
//
// + add 1 cycle if succeeds
// + add 1 cycle if page boundary crossed

fn resolve(address: u16, offset: i8) u16 {
    return @as(u16, @truncate(@as(u32, @bitCast(@as(i32, address) +% offset))));
}

pub fn bmi(self: *CPU, addressing: Addressing) void {
    if (!self.n) return;

    if (self.cycle_counter == 2) {
        self.next_cycle = .read;
        return;
    }

    switch (addressing) {
        .rel => |v| {
            if (self.cycle_counter == 3) {
                const crossed = (self.pc & 0xff00) != (resolve(self.pc, v) & 0xff00);
                if (crossed) {
                    _ = self.read((self.pc & 0xff00) | (resolve(self.pc, v) & 0xff));
                    self.next_cycle = .read;
                    return;
                }
            }

            self.pc = resolve(self.pc, v);
        },
        else => {},
    }
}
