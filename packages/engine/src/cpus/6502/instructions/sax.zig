const std = @import("std");
const CPU = @import("../cpu.zig").CPU;
const Addressing = @import("../opcode.zig").Addressing;

// extra opcode sax = st(a&x)
pub fn sax(self: *CPU, addressing: Addressing) void {
    switch (addressing) {
        .zpg, .zpx, .zpy => |v| {
            self.write(v, self.acc & self.x);
        },
        .abs => |v| {
            self.write(v, self.acc & self.x);
        },
        .idx => |v| {
            self.write(v.@"0", self.acc & self.x);
        },
        else => {},
    }
}
