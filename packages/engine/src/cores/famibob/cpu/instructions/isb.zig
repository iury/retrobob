const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// extra opcode isb
pub fn isb(self: *CPU, addressing: Addressing) void {
    const S = struct {
        var address: u16 = 0;
        var value: u8 = 0;
    };

    switch (addressing) {
        .zpg => |v| {
            S.address = v;
            if (self.cycle_counter == 3) {
                S.value = self.read(v);
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 4) {
                self.write(v, S.value);
                self.next_cycle = .write;
                return;
            }
        },
        .zpx, .zpy => |v| {
            S.address = v;
            if (self.cycle_counter == 4) {
                S.value = self.read(v);
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 5) {
                self.write(v, S.value);
                self.next_cycle = .write;
                return;
            }
        },
        .abs => |v| {
            S.address = v;
            if (self.cycle_counter == 4) {
                S.value = self.read(v);
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 5) {
                self.write(v, S.value);
                self.next_cycle = .write;
                return;
            }
        },
        .abx, .aby => |v| {
            S.address = v.@"0";
            if (self.cycle_counter == 4) {
                _ = self.read(v.@"0");
                self.next_cycle = .read;
                return;
            } else if (self.cycle_counter == 5) {
                S.value = self.read(v.@"0");
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 6) {
                self.write(v.@"0", S.value);
                self.next_cycle = .write;
                return;
            }
        },
        .idx => |v| {
            S.address = v.@"0";
            if (self.cycle_counter == 6) {
                S.value = self.read(v.@"0");
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 7) {
                self.write(v.@"0", S.value);
                self.next_cycle = .write;
                return;
            }
        },
        .idy => |v| {
            S.address = v.@"0";
            if (self.cycle_counter == 5) {
                _ = self.read(v.@"0");
                self.next_cycle = .read;
                return;
            } else if (self.cycle_counter == 6) {
                S.value = self.read(v.@"0");
                self.next_cycle = .write;
                return;
            } else if (self.cycle_counter == 7) {
                self.write(v.@"0", S.value);
                self.next_cycle = .write;
                return;
            }
        },
        else => {},
    }

    S.value +%= 1;
    self.write(S.address, S.value);

    const a = self.acc;
    const b = S.value;

    const sub1 = @subWithOverflow(a, b);
    const sub2 = @subWithOverflow(sub1.@"0", if (self.c) 0 else @as(u8, 1));
    const result = sub2.@"0";

    self.acc = result;
    self.z = result == 0;
    self.n = (result & 0x80) > 0;
    self.v = ((a ^ result) & ((255 - b) ^ result) & 0x80) > 0;
    self.c = sub1.@"1" == 0 and sub2.@"1" == 0;
}
