const testing = @import("../testing/setup.zig");

test "SBC imm" {
    var cpu = testing.createCPU();
    cpu.acc = 2;
    cpu.c = true;
    cpu.write(0, 0xe9);
    cpu.write(1, 1);
    for (0..2) |_| {
        cpu.process();
    }
    try testing.expectEqual(1, cpu.acc);
    try testing.expectEqual(true, cpu.c);
}
