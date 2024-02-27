const testing = @import("../testing/setup.zig");

test "PLA" {
    var cpu = testing.createCPU();
    cpu.sp = 0xff;
    cpu.acc = 0x42;
    cpu.write(0, 0x48);
    cpu.write(1, 0x68);
    for (0..3) |_| {
        cpu.process();
    }
    try testing.expectEqual(0xfe, cpu.sp);
    try testing.expectEqual(cpu.acc, cpu.read(0x1ff));

    cpu.acc = 0;
    for (0..4) |_| {
        cpu.process();
    }
    try testing.expectEqual(0xff, cpu.sp);
    try testing.expectEqual(0x42, cpu.acc);
}
