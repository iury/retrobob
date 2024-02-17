const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// STore Accumulator
//
// M = A
//
// MODE          SYNTAX        HEX LEN TIM
// Zero Page     STA $44       $85  2   3
// Zero Page,X   STA $44,X     $95  2   4
// Absolute      STA $4400     $8D  3   4
// Absolute,X    STA $4400,X   $9D  3   5
// Absolute,Y    STA $4400,Y   $99  3   5
// Indirect,X    STA ($44,X)   $81  2   6
// Indirect,Y    STA ($44),Y   $91  2   6

pub fn sta(self: *CPU, addressing: Addressing) void {
    switch (addressing) {
        .zpg, .zpx, .zpy => |v| {
            self.write(v, self.acc);
        },
        .abs => |v| {
            self.write(v, self.acc);
        },
        .abx, .aby => |v| {
            if (self.cycle_counter == 4) {
                _ = self.read(v.@"0");
                self.next_cycle = .write;
                return;
            }
            self.write(v.@"0", self.acc);
        },
        .idx => |v| {
            self.write(v.@"0", self.acc);
        },
        .idy => |v| {
            if (self.cycle_counter == 5) {
                _ = self.read(v.@"0");
                self.next_cycle = .write;
                return;
            }
            self.write(v.@"0", self.acc);
        },
        else => {},
    }
}
