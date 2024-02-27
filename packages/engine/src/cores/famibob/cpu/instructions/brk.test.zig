const testing = @import("../testing/setup.zig");

test "BRK" {
    var cpu = testing.createCPU();
    cpu.sp = 0xff;
    cpu.i = false;
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
}

test "BRK hijacked" {
    var cpu = testing.createCPU();
    cpu.sp = 0xff;
    cpu.i = false;
    cpu.write(0, 0);
    cpu.write(0xfffa, 4);
    cpu.write(0xfffb, 0xac);
    for (0..7) |i| {
        if (i == 1) cpu.nmi_requested = true;
        cpu.process();
    }
    try testing.expectEqual(0x4ac, cpu.pc);
    try testing.expectEqual(0, cpu.read(0x1ff));
    try testing.expectEqual(2, cpu.read(0x1fe));
    try testing.expectEqual((cpu.getP() | 0x10) & ~@as(u8, 0x4), cpu.read(0x1fd));
    try testing.expectEqual(true, cpu.i);
}
