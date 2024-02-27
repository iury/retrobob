const testing = @import("../testing/setup.zig");

test "RTS" {
    var cpu = testing.createCPU();
    cpu.sp = 0xff;
    cpu.write(0, 0x20);
    cpu.write(1, 0xac);
    cpu.write(2, 4);
    for (0..6) |_| {
        cpu.process();
    }
    try testing.expectEqual(0x4ac, cpu.pc);
    try testing.expectEqual(0, cpu.read(0x1ff));
    try testing.expectEqual(2, cpu.read(0x1fe));

    cpu.write(0x4ac, 0x60);
    for (0..6) |_| {
        cpu.process();
    }
    try testing.expectEqual(3, cpu.pc);
}
