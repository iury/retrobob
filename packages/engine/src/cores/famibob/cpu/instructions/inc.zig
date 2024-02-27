const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// INCrement memory
//
// M,Z,N = M+1
//
// Affects Flags: N Z
//
// MODE          SYNTAX        HEX LEN TIM
// Zero Page     INC $44       $E6  2   5
// Zero Page,X   INC $44,X     $F6  2   6
// Absolute      INC $4400     $EE  3   6
// Absolute,X    INC $4400,X   $FE  3   7

pub fn inc(self: *CPU, addressing: Addressing) void {
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
        else => {},
    }

    S.value +%= 1;
    self.write(S.address, S.value);
    self.z = S.value == 0;
    self.n = (S.value & 0x80) > 0;
}

test {
    _ = @import("inc.test.zig");
}
