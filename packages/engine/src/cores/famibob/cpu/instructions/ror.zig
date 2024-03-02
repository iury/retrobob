const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// ROtate Right
//
// Affects Flags: N Z C
//
// MODE          SYNTAX        HEX LEN TIM
// Accumulator   ROR A         $6A  1   2
// Zero Page     ROR $44       $66  2   5
// Zero Page,X   ROR $44,X     $76  2   6
// Absolute      ROR $4400     $6E  3   6
// Absolute,X    ROR $4400,X   $7E  3   7

pub fn ror(self: *CPU, addressing: Addressing) void {
    switch (addressing) {
        .acc => |_| {
            const c = if (self.c) @as(u8, 0x80) else 0;
            self.c = (self.acc & 0x1) > 0;
            self.acc = (self.acc >> 1) | c;
            self.z = self.acc == 0;
            self.n = (self.acc & 0x80) > 0;
            return;
        },
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

    const c = if (self.c) @as(u8, 0x80) else 0;
    self.c = (self.inst_value & 0x1) > 0;
    self.inst_value = (self.inst_value >> 1) | c;
    self.write(self.inst_address, self.inst_value);
    self.z = self.inst_value == 0;
    self.n = (self.inst_value & 0x80) > 0;
}
