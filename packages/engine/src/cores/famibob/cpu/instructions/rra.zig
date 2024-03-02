const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// extra opcode rra
pub fn rra(self: *CPU, addressing: Addressing) void {
    switch (addressing) {
        .zpg => |v| {
            self.inst_address = v;
            if (self.cycle_counter == 3) {
                self.inst_value = self.read(v);
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 4) {
                self.write(v, self.inst_value);
                self.next_cycle = .write;
                return;
            }
        },
        .zpx, .zpy => |v| {
            self.inst_address = v;
            if (self.cycle_counter == 4) {
                self.inst_value = self.read(v);
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 5) {
                self.write(v, self.inst_value);
                self.next_cycle = .write;
                return;
            }
        },
        .abs => |v| {
            self.inst_address = v;
            if (self.cycle_counter == 4) {
                self.inst_value = self.read(v);
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 5) {
                self.write(v, self.inst_value);
                self.next_cycle = .write;
                return;
            }
        },
        .abx, .aby => |v| {
            self.inst_address = v.@"0";
            if (self.cycle_counter == 4) {
                _ = self.read(v.@"0");
                self.next_cycle = .read;
                return;
            } else if (self.cycle_counter == 5) {
                self.inst_value = self.read(v.@"0");
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 6) {
                self.write(v.@"0", self.inst_value);
                self.next_cycle = .write;
                return;
            }
        },
        .idx => |v| {
            self.inst_address = v.@"0";
            if (self.cycle_counter == 6) {
                self.inst_value = self.read(v.@"0");
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 7) {
                self.write(v.@"0", self.inst_value);
                self.next_cycle = .write;
                return;
            }
        },
        .idy => |v| {
            self.inst_address = v.@"0";
            if (self.cycle_counter == 5) {
                _ = self.read(v.@"0");
                self.next_cycle = .read;
                return;
            } else if (self.cycle_counter == 6) {
                self.inst_value = self.read(v.@"0");
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 7) {
                self.write(v.@"0", self.inst_value);
                self.next_cycle = .write;
                return;
            }
        },
        else => {},
    }

    const c = if (self.c) @as(u8, 0x80) else 0;
    self.c = (self.inst_value & 0x1) > 0;
    self.inst_value = (self.inst_value >> 1) | c;
    self.write(self.inst_address, self.inst_value);

    const a = self.acc;
    const b = self.inst_value;

    const sum1 = @addWithOverflow(a, b);
    const sum2 = @addWithOverflow(sum1.@"0", if (self.c) @as(u8, 1) else 0);
    const result = sum2.@"0";

    self.acc = result;
    self.z = result == 0;
    self.n = (result & 0x80) > 0;
    self.v = ((a ^ result) & (b ^ result) & 0x80) > 0;
    self.c = sum1.@"1" == 1 or sum2.@"1" == 1;
}
