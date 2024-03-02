const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// DECrement memory
//
// M,Z,N = M-1
//
// Affects Flags: N Z
//
// MODE          SYNTAX        HEX LEN TIM
// Zero Page     DEC $44       $C6  2   5
// Zero Page,X   DEC $44,X     $D6  2   6
// Absolute      DEC $4400     $CE  3   6
// Absolute,X    DEC $4400,X   $DE  3   7

pub fn dec(self: *CPU, addressing: Addressing) void {
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
        else => {},
    }

    self.inst_value -%= 1;
    self.write(self.inst_address, self.inst_value);
    self.z = self.inst_value == 0;
    self.n = (self.inst_value & 0x80) > 0;
}

test {
    _ = @import("dec.test.zig");
}
