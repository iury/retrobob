const testing = @import("../testing/setup.zig");

test "PLP" {
    var cpu = testing.createCPU();
    cpu.sp = 0xff;
    cpu.z = true;
    cpu.write(0, 0x8);
    cpu.write(1, 0x28);
    for (0..3) |_| {
        cpu.process();
    }
    try testing.expectEqual(0xfe, cpu.sp);
    try testing.expectEqual(cpu.getP() | 0x10, cpu.read(0x1ff));

    cpu.z = false;
    for (0..4) |_| {
        cpu.process();
    }
    try testing.expectEqual(0xff, cpu.sp);
    try testing.expectEqual(false, cpu.b);
    try testing.expectEqual(true, cpu.z);
}
