const testing = @import("../testing/setup.zig");

test "RTI" {
    var cpu = testing.createCPU();
    cpu.sp = 0xff;
    cpu.i = false;
    cpu.z = true;
    cpu.write(0, 0);
    cpu.write(0xfffe, 4);
    cpu.write(0xffff, 0xac);
    for (0..7) |_| {
        cpu.process();
    }
    try testing.expectEqual(0x4ac, cpu.pc);
    try testing.expectEqual(0, cpu.read(0x1ff));
    try testing.expectEqual(2, cpu.read(0x1fe));
    try testing.expectEqual((cpu.getP() | 0x10) & ~@as(u8, 0x4), cpu.read(0x1fd));
    try testing.expectEqual(true, cpu.i);

    cpu.write(0x4ac, 0x40);
    cpu.z = false;
    for (0..6) |_| {
        cpu.process();
    }
    try testing.expectEqual(2, cpu.pc);
    try testing.expectEqual(true, cpu.z);
    try testing.expectEqual(false, cpu.i);
}
