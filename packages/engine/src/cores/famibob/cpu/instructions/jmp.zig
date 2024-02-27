const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;
const Opcodes = @import("../opcode.zig").Opcodes;

// JuMP
//
// MODE          SYNTAX        HEX LEN TIM
// Absolute      JMP $5597     $4C  3   3
// Indirect      JMP ($5597)   $6C  3   5

pub fn jmp(self: *CPU, addressing: Addressing) void {
    const inst = Opcodes[self.opcode];
    if (inst.addressing_mode == .abs) {
        if (self.cycle_counter == 2) {
            self.addressing = .{ .abs = self.fetch() };
            self.next_cycle = .read;
            return;
        } else {
            switch (addressing) {
                .abs => |v| {
                    self.pc = (@as(u16, self.fetch()) << 8) | v;
                },
                else => {},
            }
        }
    } else {
        if (self.cycle_counter == 2) {
            self.addressing = .{ .idx = .{ self.fetch(), 0 } };
            self.next_cycle = .read;
            return;
        } else {
            switch (addressing) {
                .idx => |v| {
                    if (self.cycle_counter == 3) {
                        self.addressing = .{ .idx = .{ (@as(u16, self.fetch()) << 8) | v.@"0", 0 } };
                        self.next_cycle = .read;
                        return;
                    } else if (self.cycle_counter == 4) {
                        self.addressing = .{ .idx = .{ v.@"0", self.read(v.@"0") } };
                        self.next_cycle = .read;
                        return;
                    } else if (self.cycle_counter == 5) {
                        var addr = v.@"0";
                        if ((addr & 0xff) == 0xff) {
                            addr &= 0xff00;
                        } else {
                            addr += 1;
                        }
                        self.pc = (@as(u16, self.read(addr)) << 8) | v.@"1";
                    }
                },
                else => {},
            }
        }
    }
}

test {
    _ = @import("jmp.test.zig");
}
