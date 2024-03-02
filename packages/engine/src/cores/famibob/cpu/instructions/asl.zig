const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// Arithmetic Shift Left
//
// A,Z,C,N = M*2 or M,Z,C,N = M*2
//
// Affects Flags: N Z C
//
// MODE          SYNTAX        HEX LEN TIM
// Accumulator   ASL A         $0A  1   2
// Zero Page     ASL $44       $06  2   5
// Zero Page,X   ASL $44,X     $16  2   6
// Absolute      ASL $4400     $0E  3   6
// Absolute,X    ASL $4400,X   $1E  3   7

pub fn asl(self: *CPU, addressing: Addressing) void {
    switch (addressing) {
        .acc => |_| {
            self.c = (self.acc & 0x80) > 0;
            self.acc <<= 1;
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

    var b = self.inst_value;
    self.c = (b & 0x80) > 0;
    b <<= 1;
    self.write(self.inst_address, b);
    self.z = b == 0;
    self.n = (b & 0x80) > 0;
}

test {
    _ = @import("asl.test.zig");
}
