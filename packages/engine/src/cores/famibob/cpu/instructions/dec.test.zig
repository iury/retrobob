const testing = @import("../testing/setup.zig");

test "DEC" {
    var cpu = testing.createCPU();
    cpu.write(0, 0xc6);
    cpu.write(1, 2);
    cpu.write(2, 0);
    for (0..5) |_| {
        cpu.process();
    }
    try testing.expectEqual(255, cpu.read(2));
}
